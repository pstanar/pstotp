import { describe, it, expect } from "vitest";
import {
  encryptIconLibrary,
  decryptIconLibrary,
} from "@/features/vault/utils/icon-library-crypto";
import type { IconLibraryBlob } from "@/types/icon-library";
import { generateVaultKey } from "@/lib/crypto";

describe("icon-library crypto", () => {
  const sampleBlob: IconLibraryBlob = {
    version: 1,
    icons: [
      {
        id: "11111111-1111-1111-1111-111111111111",
        label: "Company logo",
        data: "data:image/png;base64,iVBORw0KGgo=",
        createdAt: "2026-04-22T00:00:00.000Z",
      },
      {
        id: "22222222-2222-2222-2222-222222222222",
        label: "Another",
        data: "data:image/png;base64,XYZ=",
        createdAt: "2026-04-22T01:00:00.000Z",
      },
    ],
  };

  it("round-trips a blob through encrypt + decrypt", async () => {
    const key = generateVaultKey();
    const encrypted = await encryptIconLibrary(key, sampleBlob);
    expect(encrypted).toMatch(/^[A-Za-z0-9+/=]+$/); // base64

    const decrypted = await decryptIconLibrary(key, encrypted);
    expect(decrypted).toEqual(sampleBlob);
  });

  it("produces different ciphertext each call (fresh nonce)", async () => {
    const key = generateVaultKey();
    const a = await encryptIconLibrary(key, sampleBlob);
    const b = await encryptIconLibrary(key, sampleBlob);
    expect(a).not.toEqual(b);
  });

  it("decrypting with a different key throws", async () => {
    const key1 = generateVaultKey();
    const key2 = generateVaultKey();
    const encrypted = await encryptIconLibrary(key1, sampleBlob);
    await expect(decryptIconLibrary(key2, encrypted)).rejects.toThrow();
  });

  it("handles the empty-library case", async () => {
    const key = generateVaultKey();
    const empty: IconLibraryBlob = { version: 1, icons: [] };
    const encrypted = await encryptIconLibrary(key, empty);
    const decrypted = await decryptIconLibrary(key, encrypted);
    expect(decrypted).toEqual(empty);
  });
});
