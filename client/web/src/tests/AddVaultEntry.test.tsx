import { describe, it, expect, afterEach } from "vitest";
import { encryptEntry, decryptEntry } from "@/features/vault/utils/vault-crypto";
import { generateVaultKey } from "@/lib/crypto";
import { useVaultStore } from "@/stores/useVaultStore";
import type { VaultEntryPlaintext } from "@/types/vault-types";

const sampleEntry: VaultEntryPlaintext = {
  issuer: "GitHub",
  accountName: "alice@example.com",
  secret: "JBSWY3DPEHPK3PXP",
  algorithm: "SHA1",
  digits: 6,
  period: 30,
};

afterEach(() => {
  useVaultStore.getState().lock();
});

describe("AddVaultEntry", () => {
  it("encrypts entry with vault key and entry ID as associated data", async () => {
    const key = generateVaultKey();
    const entryId = crypto.randomUUID();

    const payload = await encryptEntry(key, sampleEntry, entryId);

    expect(typeof payload).toBe("string");
    expect(payload.length).toBeGreaterThan(0);

    const decrypted = await decryptEntry(key, payload, entryId);
    expect(decrypted.issuer).toBe("GitHub");
    expect(decrypted.secret).toBe("JBSWY3DPEHPK3PXP");
  });

  it("fails to decrypt with wrong entry ID (AEAD binding)", async () => {
    const key = generateVaultKey();
    const entryId = crypto.randomUUID();
    const wrongId = crypto.randomUUID();

    const payload = await encryptEntry(key, sampleEntry, entryId);

    await expect(decryptEntry(key, payload, wrongId)).rejects.toThrow();
  });

  it("adds entry to vault store on success", () => {
    useVaultStore.getState().unlock([]);
    useVaultStore.getState().addEntry({
      ...sampleEntry,
      id: "test-id-1",
      version: 1,
    });

    const entries = useVaultStore.getState().entries;
    expect(entries).toHaveLength(1);
    expect(entries[0].issuer).toBe("GitHub");
    expect(entries[0].id).toBe("test-id-1");
  });

  it("preserves optional icon field through encrypt/decrypt", async () => {
    const key = generateVaultKey();
    const entryId = crypto.randomUUID();
    const withIcon = { ...sampleEntry, icon: "\u{1F512}" };

    const payload = await encryptEntry(key, withIcon, entryId);
    const decrypted = await decryptEntry(key, payload, entryId);

    expect(decrypted.icon).toBe("\u{1F512}");
  });
});
