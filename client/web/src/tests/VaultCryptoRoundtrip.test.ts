import { describe, it, expect } from "vitest";
import { encryptEntry, decryptEntry } from "@/features/vault/utils/vault-crypto";
import { generateVaultKey } from "@/lib/crypto";
import type { VaultEntryPlaintext } from "@/types/vault-types";

describe("vault entry encrypt/decrypt", () => {
  const sampleEntry: VaultEntryPlaintext = {
    issuer: "GitHub",
    accountName: "alice@example.com",
    secret: "JBSWY3DPEHPK3PXP",
    algorithm: "SHA1",
    digits: 6,
    period: 30,
  };

  it("roundtrips encrypt → decrypt", async () => {
    const key = generateVaultKey();
    const entryId = crypto.randomUUID();

    const payload = await encryptEntry(key, sampleEntry, entryId);
    const decrypted = await decryptEntry(key, payload, entryId);

    expect(decrypted).toEqual(sampleEntry);
  });

  it("fails with wrong vault key", async () => {
    const key = generateVaultKey();
    const wrongKey = generateVaultKey();
    const entryId = crypto.randomUUID();

    const payload = await encryptEntry(key, sampleEntry, entryId);

    await expect(decryptEntry(wrongKey, payload, entryId)).rejects.toThrow();
  });

  it("fails with wrong entry ID (associated data mismatch)", async () => {
    const key = generateVaultKey();
    const entryId = crypto.randomUUID();
    const wrongId = crypto.randomUUID();

    const payload = await encryptEntry(key, sampleEntry, entryId);

    await expect(decryptEntry(key, payload, wrongId)).rejects.toThrow();
  });

  it("preserves all fields including optional icon", async () => {
    const key = generateVaultKey();
    const entryId = crypto.randomUUID();
    const entryWithIcon: VaultEntryPlaintext = {
      ...sampleEntry,
      icon: "\u{1F512}",
    };

    const payload = await encryptEntry(key, entryWithIcon, entryId);
    const decrypted = await decryptEntry(key, payload, entryId);

    expect(decrypted).toEqual(entryWithIcon);
  });

  it("produces different payloads for same entry (random nonce)", async () => {
    const key = generateVaultKey();
    const entryId = crypto.randomUUID();

    const p1 = await encryptEntry(key, sampleEntry, entryId);
    const p2 = await encryptEntry(key, sampleEntry, entryId);

    expect(p1).not.toBe(p2);
  });
});
