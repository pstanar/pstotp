import { describe, it, expect, beforeEach, vi } from "vitest";
import { generateVaultKey, sha256Hex } from "@/lib/crypto";
import { MAX_LIBRARY_ICONS } from "@/types/icon-library";

// Mock the server API so saveLibrary/load don't hit the network. fetch
// returns "no library yet"; put echoes an incremented version.
vi.mock("@/features/vault/api/icon-library-api", () => ({
  fetchIconLibrary: vi.fn(async () => ({ encryptedPayload: "", version: 0, updatedAt: null })),
  putIconLibrary: vi.fn(async (_payload: string, expectedVersion: number) => ({
    version: expectedVersion + 1,
    updatedAt: "2026-01-01T00:00:00.000Z",
  })),
}));

import { useIconLibraryStore } from "@/stores/useIconLibraryStore";
import { putIconLibrary, fetchIconLibrary } from "@/features/vault/api/icon-library-api";
import { encryptIconLibrary } from "@/features/vault/utils/icon-library-crypto";

const key = generateVaultKey();
const put = vi.mocked(putIconLibrary);

beforeEach(() => {
  useIconLibraryStore.getState().clear();
  put.mockClear();
});

describe("sha256Hex", () => {
  it("matches the known digest of 'abc'", async () => {
    const hex = await sha256Hex(new TextEncoder().encode("abc"));
    expect(hex).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  });
});

describe("icon-library store dedup", () => {
  it("adds a new icon with both hashes and persists once", async () => {
    const id = await useIconLibraryStore.getState().addIcon(key, "Logo", "data:image/png;base64,AAA", {
      sourceBytes: new Uint8Array([1, 2, 3]),
    });
    const icons = useIconLibraryStore.getState().icons;
    expect(icons).toHaveLength(1);
    expect(icons[0].id).toBe(id);
    expect(icons[0].dataHash).toBeDefined();
    expect(icons[0].sourceHash).toBeDefined();
    expect(put).toHaveBeenCalledTimes(1);
  });

  it("de-dups by dataHash (identical data URL) without a second write", async () => {
    const id1 = await useIconLibraryStore.getState().addIcon(key, "A", "data:image/png;base64,SAME");
    put.mockClear();
    const id2 = await useIconLibraryStore.getState().addIcon(key, "B", "data:image/png;base64,SAME");
    expect(id2).toBe(id1);
    expect(useIconLibraryStore.getState().icons).toHaveLength(1);
    expect(put).not.toHaveBeenCalled();
  });

  it("de-dups by sourceHash even when the resized data URL differs", async () => {
    const src = new Uint8Array([9, 8, 7]);
    const id1 = await useIconLibraryStore.getState().addIcon(key, "A", "data:image/png;base64,ONE", { sourceBytes: src });
    put.mockClear();
    const id2 = await useIconLibraryStore.getState().addIcon(key, "B", "data:image/png;base64,TWO", { sourceBytes: src });
    expect(id2).toBe(id1);
    expect(useIconLibraryStore.getState().icons).toHaveLength(1);
    expect(put).not.toHaveBeenCalled();
  });
});

describe("icon-library store batch", () => {
  it("dedups within the batch and against existing, persisting once", async () => {
    await useIconLibraryStore.getState().load(key); // unlock loads first in the real app
    await useIconLibraryStore.getState().addIcon(key, "existing", "data:image/png;base64,EXIST");
    put.mockClear();

    const result = await useIconLibraryStore.getState().addIconsBatch(key, [
      { label: "new1", dataUrl: "data:image/png;base64,N1" },
      { label: "dup-of-new1", dataUrl: "data:image/png;base64,N1" }, // within-batch dup
      { label: "dup-existing", dataUrl: "data:image/png;base64,EXIST" }, // existing dup
      { label: "new2", dataUrl: "data:image/png;base64,N2" },
    ]);

    expect(result).toEqual({ added: 2, duplicates: 2, overflow: 0 });
    expect(useIconLibraryStore.getState().icons).toHaveLength(3);
    expect(put).toHaveBeenCalledTimes(1); // single batched write
  });

  it("backfills dataHash for legacy icons on load (sourceHash stays absent)", async () => {
    const legacy = {
      version: 1 as const,
      icons: [
        { id: "legacy-1", label: "Old", data: "data:image/png;base64,LEG", createdAt: "2026-01-01T00:00:00.000Z" },
      ],
    };
    const payload = await encryptIconLibrary(key, legacy);
    vi.mocked(fetchIconLibrary).mockResolvedValueOnce({ encryptedPayload: payload, version: 7, updatedAt: null });

    await useIconLibraryStore.getState().load(key);

    const icon = useIconLibraryStore.getState().icons[0];
    expect(icon.dataHash).toBe(await sha256Hex(new TextEncoder().encode("data:image/png;base64,LEG")));
    expect(icon.sourceHash).toBeUndefined();
  });

  it("counts items beyond the count cap as overflow", async () => {
    const items = Array.from({ length: MAX_LIBRARY_ICONS + 5 }, (_, i) => ({
      label: `icon-${i}`,
      dataUrl: `data:image/png;base64,UNIQUE${i}`,
    }));
    const result = await useIconLibraryStore.getState().addIconsBatch(key, items);
    expect(result.added).toBe(MAX_LIBRARY_ICONS);
    expect(result.overflow).toBe(5);
    expect(useIconLibraryStore.getState().icons).toHaveLength(MAX_LIBRARY_ICONS);
  });

  it("fails closed when the library load fails — no destructive write", async () => {
    // A transient load failure must NOT be treated as an empty library, or a
    // batch save would overwrite the user's real server-side library.
    vi.mocked(fetchIconLibrary).mockRejectedValueOnce(new Error("network down"));
    await expect(
      useIconLibraryStore.getState().addIconsBatch(key, [
        { label: "x", dataUrl: "data:image/png;base64,Z" },
      ]),
    ).rejects.toThrow();
    expect(put).not.toHaveBeenCalled();
    expect(useIconLibraryStore.getState().loaded).toBe(false);
  });
});
