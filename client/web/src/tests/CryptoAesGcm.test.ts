import { describe, it, expect } from "vitest";
import {
  aesGcmEncrypt,
  aesGcmDecrypt,
  generateVaultKey,
  generateRandomBytes,
} from "@/lib/crypto";

describe("AES-256-GCM", () => {
  it("roundtrips encrypt → decrypt", async () => {
    const key = generateVaultKey();
    const plaintext = new TextEncoder().encode("hello world");

    const { ciphertext, nonce } = await aesGcmEncrypt(key, plaintext);
    const decrypted = await aesGcmDecrypt(key, ciphertext, nonce);

    expect(Array.from(decrypted)).toEqual(Array.from(plaintext));
  });

  it("produces different ciphertext each time (random nonce)", async () => {
    const key = generateVaultKey();
    const plaintext = new TextEncoder().encode("same data");

    const r1 = await aesGcmEncrypt(key, plaintext);
    const r2 = await aesGcmEncrypt(key, plaintext);

    expect(Array.from(r1.nonce)).not.toEqual(Array.from(r2.nonce));
    expect(Array.from(r1.ciphertext)).not.toEqual(Array.from(r2.ciphertext));
  });

  it("fails to decrypt with wrong key", async () => {
    const key = generateVaultKey();
    const wrongKey = generateVaultKey();
    const plaintext = new TextEncoder().encode("secret");

    const { ciphertext, nonce } = await aesGcmEncrypt(key, plaintext);

    await expect(aesGcmDecrypt(wrongKey, ciphertext, nonce)).rejects.toThrow();
  });

  it("fails to decrypt tampered ciphertext", async () => {
    const key = generateVaultKey();
    const plaintext = new TextEncoder().encode("data");

    const { ciphertext, nonce } = await aesGcmEncrypt(key, plaintext);
    ciphertext[0] ^= 0xff;

    await expect(aesGcmDecrypt(key, ciphertext, nonce)).rejects.toThrow();
  });

  it("roundtrips with associated data", async () => {
    const key = generateVaultKey();
    const plaintext = new TextEncoder().encode("payload");
    const ad = new TextEncoder().encode("entry-id-123");

    const { ciphertext, nonce } = await aesGcmEncrypt(key, plaintext, ad);
    const decrypted = await aesGcmDecrypt(key, ciphertext, nonce, ad);

    expect(Array.from(decrypted)).toEqual(Array.from(plaintext));
  });

  it("fails to decrypt with wrong associated data", async () => {
    const key = generateVaultKey();
    const plaintext = new TextEncoder().encode("payload");
    const ad = new TextEncoder().encode("correct-id");
    const wrongAd = new TextEncoder().encode("wrong-id");

    const { ciphertext, nonce } = await aesGcmEncrypt(key, plaintext, ad);

    await expect(aesGcmDecrypt(key, ciphertext, nonce, wrongAd)).rejects.toThrow();
  });

  it("nonce is 12 bytes", async () => {
    const key = generateVaultKey();
    const plaintext = generateRandomBytes(32);

    const { nonce } = await aesGcmEncrypt(key, plaintext);
    expect(nonce.length).toBe(12);
  });

  it("ciphertext includes 16-byte auth tag", async () => {
    const key = generateVaultKey();
    const plaintext = generateRandomBytes(32);

    const { ciphertext } = await aesGcmEncrypt(key, plaintext);
    // ciphertext = encrypted data (32 bytes) + tag (16 bytes) = 48 bytes
    expect(ciphertext.length).toBe(32 + 16);
  });
});
