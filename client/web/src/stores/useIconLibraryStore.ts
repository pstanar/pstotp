import { create } from "zustand";
import type { LibraryIcon } from "@/types/icon-library";
import { MAX_LIBRARY_ICONS, MAX_LIBRARY_BYTES } from "@/types/icon-library";
import {
  fetchIconLibrary,
  putIconLibrary,
} from "@/features/vault/api/icon-library-api";
import { ApiError } from "@/lib/api-client";
import { sha256Hex } from "@/lib/crypto";
import {
  encryptIconLibrary,
  decryptIconLibrary,
} from "@/features/vault/utils/icon-library-crypto";

/**
 * Bytes AES-GCM packing adds on top of the plaintext: nonce(12) + tag(16).
 * The server caps the *encrypted* payload, so the plaintext JSON budget must
 * reserve this or a near-limit write passes here and 400s server-side.
 */
const AEAD_OVERHEAD_BYTES = 28;
const MAX_PLAINTEXT_BYTES = MAX_LIBRARY_BYTES - AEAD_OVERHEAD_BYTES;

/** One icon to add via addIcon / addIconsBatch, before it gets an id. */
export interface IconInput {
  label: string;
  dataUrl: string;
  /** Raw pre-resize bytes, when available — enables a stable sourceHash. */
  sourceBytes?: Uint8Array | null;
}

/** Outcome of a batch add, for user-facing reporting. */
export interface BatchAddResult {
  added: number;
  duplicates: number;
  overflow: number; // skipped because the count or byte cap was reached
}

/**
 * Client state for the user's custom icon library. Loaded on vault
 * unlock, kept in memory alongside the vault key. Every mutation
 * encrypts + uploads the full blob with optimistic concurrency; a
 * 409 from the server triggers a transparent refetch + retry once.
 */
interface IconLibraryState {
  icons: LibraryIcon[];
  serverVersion: number; // last version the server acknowledged
  loaded: boolean;
  loadError: string | null;
}

interface IconLibraryActions {
  /** Load + decrypt the library. Safe to call multiple times. */
  load: (vaultKey: Uint8Array) => Promise<void>;
  /**
   * Add a new icon and persist. De-duplicates on content: if an existing
   * icon matches by either hash, returns that icon's id without adding.
   * Returns the (new or existing) icon's id.
   */
  addIcon: (
    vaultKey: Uint8Array,
    label: string,
    dataUrl: string,
    opts?: { sourceBytes?: Uint8Array | null },
  ) => Promise<string>;
  /**
   * Add many icons in one persisted write (one encrypt + PUT). De-dups
   * against the existing library AND within the batch; respects the count
   * and byte caps, counting skipped icons as overflow. Used by import.
   */
  addIconsBatch: (vaultKey: Uint8Array, items: IconInput[]) => Promise<BatchAddResult>;
  /** Remove by id. Existing vault entries that used the icon keep their own copy. */
  removeIcon: (vaultKey: Uint8Array, id: string) => Promise<void>;
  /** Rename an existing icon's label. */
  renameIcon: (vaultKey: Uint8Array, id: string, label: string) => Promise<void>;
  /** Drop in-memory state (called from useVaultStore.lock). */
  clear: () => void;
}

const initialState: IconLibraryState = {
  icons: [],
  serverVersion: 0,
  loaded: false,
  loadError: null,
};

export const useIconLibraryStore = create<IconLibraryStore>()((set, get) => ({
  ...initialState,

  load: async (vaultKey) => {
    if (get().loaded) return;
    try {
      const response = await fetchIconLibrary();
      if (response.version === 0 || response.encryptedPayload === "") {
        set({ icons: [], serverVersion: 0, loaded: true, loadError: null });
        return;
      }
      const blob = await decryptIconLibrary(vaultKey, response.encryptedPayload);
      // Backfill dataHash for legacy icons that predate content hashing.
      // In-memory only — persisted on the next mutation. sourceHash can't
      // be backfilled (the original pre-resize bytes are long gone).
      const icons = await backfillHashes(blob.icons);
      set({
        icons,
        serverVersion: response.version,
        loaded: true,
        loadError: null,
      });
    } catch (err) {
      // Fail closed: leave loaded=false so the load is retried and, crucially,
      // so mutations don't build on a synthetic empty library. Treating a
      // transient fetch/decrypt failure as "library is empty" would let a
      // subsequent save (via the 409 last-write-wins retry) overwrite the
      // user's real server-side library.
      set({
        icons: [],
        serverVersion: 0,
        loaded: false,
        loadError: err instanceof Error ? err.message : "Failed to load icon library",
      });
    }
  },

  addIcon: async (vaultKey, label, dataUrl, opts) => {
    if (!get().loaded) await get().load(vaultKey);
    if (!get().loaded) throw new Error(get().loadError ?? "Icon library is unavailable.");
    const { icons } = get();
    const fp = await fingerprint(dataUrl, opts?.sourceBytes);
    const dup = matchExisting(icons, fp);
    if (dup) return dup.id;
    if (icons.length >= MAX_LIBRARY_ICONS) {
      throw new Error(`Icon library is full (${MAX_LIBRARY_ICONS} max). Delete some icons first.`);
    }
    const icon = makeIcon(label, dataUrl, fp);
    const next = [...icons, icon];
    if (blobByteLength(next) > MAX_PLAINTEXT_BYTES) {
      throw new Error("Icon library is full (size limit). Delete some icons first.");
    }
    await saveLibrary(vaultKey, next, get, set);
    return icon.id;
  },

  addIconsBatch: async (vaultKey, items) => {
    if (!get().loaded) await get().load(vaultKey);
    if (!get().loaded) throw new Error(get().loadError ?? "Icon library is unavailable.");
    const next = [...get().icons];
    let added = 0;
    let duplicates = 0;
    let overflow = 0;
    // Track the JSON byte total incrementally — adding one icon costs its own
    // serialised length plus a separator — rather than re-serialising the whole
    // growing list on every item.
    let bytes = blobByteLength(next);
    for (const item of items) {
      const fp = await fingerprint(item.dataUrl, item.sourceBytes);
      if (matchExisting(next, fp)) {
        duplicates++;
        continue;
      }
      if (next.length >= MAX_LIBRARY_ICONS) {
        overflow++;
        continue;
      }
      const candidate = makeIcon(item.label, item.dataUrl, fp);
      const cost = new TextEncoder().encode(JSON.stringify(candidate)).length + 1;
      if (bytes + cost > MAX_PLAINTEXT_BYTES) {
        overflow++;
        continue;
      }
      next.push(candidate);
      bytes += cost;
      added++;
    }
    if (added > 0) await saveLibrary(vaultKey, next, get, set);
    return { added, duplicates, overflow };
  },

  removeIcon: async (vaultKey, id) => {
    const next = get().icons.filter((i) => i.id !== id);
    await saveLibrary(vaultKey, next, get, set);
  },

  renameIcon: async (vaultKey, id, label) => {
    const next = get().icons.map((i) =>
      i.id === id ? { ...i, label: label.trim() || i.label } : i,
    );
    await saveLibrary(vaultKey, next, get, set);
  },

  clear: () => set(initialState),
}));

type IconLibraryStore = IconLibraryState & IconLibraryActions;

/**
 * Shared save path: encrypt + PUT with the current server version, then
 * update local state with the new version the server returned. On 409
 * (version stale — another device wrote) we refetch once and try again.
 */
async function saveLibrary(
  vaultKey: Uint8Array,
  icons: LibraryIcon[],
  get: () => IconLibraryStore,
  set: (partial: Partial<IconLibraryState>) => void,
): Promise<void> {
  const blob = { version: 1 as const, icons };
  const encrypted = await encryptIconLibrary(vaultKey, blob);
  try {
    const updated = await putIconLibrary(encrypted, get().serverVersion);
    set({ icons, serverVersion: updated.version });
    return;
  } catch (err) {
    // Only treat a real 409 as a concurrency conflict. Matching on the
    // message text would miss the server's current body shape and let
    // genuine errors silently become silent refetch-and-retries.
    if (!(err instanceof ApiError) || err.status !== 409) {
      throw err;
    }
  }
  // Refetch-and-retry once — last-write-wins per project policy.
  const response = await fetchIconLibrary();
  const encrypted2 = await encryptIconLibrary(vaultKey, blob);
  const updated = await putIconLibrary(encrypted2, response.version);
  set({ icons, serverVersion: updated.version });
}

interface Fingerprint {
  dataHash: string;
  sourceHash?: string;
}

/** Hash the resized data-URL (always) and the raw source bytes (if given). */
async function fingerprint(
  dataUrl: string,
  sourceBytes?: Uint8Array | null,
): Promise<Fingerprint> {
  const dataHash = await sha256Hex(new TextEncoder().encode(dataUrl));
  const sourceHash = sourceBytes ? await sha256Hex(sourceBytes) : undefined;
  return { dataHash, sourceHash };
}

/**
 * Match-if-either: an existing icon is a duplicate when its dataHash equals
 * the candidate's, or both have a sourceHash and those match. Undefined
 * hashes never match (legacy icons lack sourceHash; missing != equal).
 */
function matchExisting(icons: LibraryIcon[], fp: Fingerprint): LibraryIcon | undefined {
  return icons.find(
    (i) =>
      (i.dataHash !== undefined && i.dataHash === fp.dataHash) ||
      (i.sourceHash !== undefined && fp.sourceHash !== undefined && i.sourceHash === fp.sourceHash),
  );
}

function makeIcon(label: string, dataUrl: string, fp: Fingerprint): LibraryIcon {
  return {
    id: crypto.randomUUID(),
    label: label.trim() || "Icon",
    data: dataUrl,
    createdAt: new Date().toISOString(),
    dataHash: fp.dataHash,
    sourceHash: fp.sourceHash,
  };
}

/**
 * Approximate encrypted-payload size: the plaintext JSON byte length. AES-GCM
 * adds only a fixed nonce+tag, so this tracks the server's 2 MB ceiling
 * closely enough to gate adds before the server would 400.
 */
function blobByteLength(icons: LibraryIcon[]): number {
  return new TextEncoder().encode(JSON.stringify({ version: 1, icons })).length;
}

/** Compute dataHash for any icon missing it (legacy blobs). */
function backfillHashes(icons: LibraryIcon[]): Promise<LibraryIcon[]> {
  return Promise.all(
    icons.map(async (i) =>
      i.dataHash !== undefined
        ? i
        : { ...i, dataHash: await sha256Hex(new TextEncoder().encode(i.data)) },
    ),
  );
}
