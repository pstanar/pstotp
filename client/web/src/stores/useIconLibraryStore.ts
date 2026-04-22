import { create } from "zustand";
import type { LibraryIcon } from "@/types/icon-library";
import { MAX_LIBRARY_ICONS } from "@/types/icon-library";
import {
  fetchIconLibrary,
  putIconLibrary,
} from "@/features/vault/api/icon-library-api";
import { ApiError } from "@/lib/api-client";
import {
  encryptIconLibrary,
  decryptIconLibrary,
} from "@/features/vault/utils/icon-library-crypto";

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
  /** Add a new icon and persist. Returns the new icon's id. */
  addIcon: (vaultKey: Uint8Array, label: string, dataUrl: string) => Promise<string>;
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
      set({
        icons: blob.icons,
        serverVersion: response.version,
        loaded: true,
        loadError: null,
      });
    } catch (err) {
      set({
        icons: [],
        serverVersion: 0,
        loaded: true,
        loadError: err instanceof Error ? err.message : "Failed to load icon library",
      });
    }
  },

  addIcon: async (vaultKey, label, dataUrl) => {
    const { icons } = get();
    if (icons.length >= MAX_LIBRARY_ICONS) {
      throw new Error(`Icon library is full (${MAX_LIBRARY_ICONS} max). Delete some icons first.`);
    }
    const id = crypto.randomUUID();
    const icon: LibraryIcon = {
      id,
      label: label.trim() || "Icon",
      data: dataUrl,
      createdAt: new Date().toISOString(),
    };
    const next = [...icons, icon];
    await saveLibrary(vaultKey, next, get, set);
    return id;
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
