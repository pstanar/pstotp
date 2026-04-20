import { describe, it, expect } from "vitest";
import {
  generateEcdhKeyPair,
  exportEcdhPublicKey,
  importEcdhPublicKey,
  deriveEcdhWrappingKey,
  packEcdhDeviceEnvelope,
  unpackEcdhDeviceEnvelope,
  generateVaultKey,
  ECDH_PUBLIC_KEY_LENGTH,
} from "@/lib/crypto";

describe("ECDH key exchange", () => {
  it("generates a P-256 key pair", async () => {
    const keyPair = await generateEcdhKeyPair();
    expect(keyPair.publicKey).toBeDefined();
    expect(keyPair.privateKey).toBeDefined();
  });

  it("exports public key as 65 bytes (uncompressed P-256)", async () => {
    const keyPair = await generateEcdhKeyPair();
    const pubBytes = await exportEcdhPublicKey(keyPair.publicKey);
    expect(pubBytes.length).toBe(ECDH_PUBLIC_KEY_LENGTH);
    expect(pubBytes[0]).toBe(0x04); // Uncompressed point prefix
  });

  it("roundtrips public key export → import", async () => {
    const keyPair = await generateEcdhKeyPair();
    const pubBytes = await exportEcdhPublicKey(keyPair.publicKey);
    const imported = await importEcdhPublicKey(pubBytes);
    const reExported = await exportEcdhPublicKey(imported);
    expect(Array.from(reExported)).toEqual(Array.from(pubBytes));
  });

  it("derives same shared key from both sides", async () => {
    const alice = await generateEcdhKeyPair();
    const bob = await generateEcdhKeyPair();

    const keyAB = await deriveEcdhWrappingKey(alice.privateKey, bob.publicKey);
    const keyBA = await deriveEcdhWrappingKey(bob.privateKey, alice.publicKey);

    expect(Array.from(keyAB)).toEqual(Array.from(keyBA));
    expect(keyAB.length).toBe(32);
  });

  it("different key pairs produce different shared keys", async () => {
    const alice = await generateEcdhKeyPair();
    const bob = await generateEcdhKeyPair();
    const charlie = await generateEcdhKeyPair();

    const keyAB = await deriveEcdhWrappingKey(alice.privateKey, bob.publicKey);
    const keyAC = await deriveEcdhWrappingKey(alice.privateKey, charlie.publicKey);

    expect(Array.from(keyAB)).not.toEqual(Array.from(keyAC));
  });
});

describe("ECDH device envelope", () => {
  it("roundtrips pack → unpack", async () => {
    const vaultKey = generateVaultKey();
    const deviceKeyPair = await generateEcdhKeyPair();

    // Approver packs for the device's public key
    const { ciphertext, nonce } = await packEcdhDeviceEnvelope(
      vaultKey,
      deviceKeyPair.publicKey,
    );

    // Device unpacks with its private key
    const recovered = await unpackEcdhDeviceEnvelope(
      ciphertext,
      nonce,
      deviceKeyPair.privateKey,
    );

    expect(Array.from(recovered)).toEqual(Array.from(vaultKey));
  });

  it("fails with wrong private key", async () => {
    const vaultKey = generateVaultKey();
    const deviceKeyPair = await generateEcdhKeyPair();
    const wrongKeyPair = await generateEcdhKeyPair();

    const { ciphertext, nonce } = await packEcdhDeviceEnvelope(
      vaultKey,
      deviceKeyPair.publicKey,
    );

    await expect(
      unpackEcdhDeviceEnvelope(ciphertext, nonce, wrongKeyPair.privateKey),
    ).rejects.toThrow();
  });

  it("ciphertext contains ephemeral public key prefix", async () => {
    const vaultKey = generateVaultKey();
    const deviceKeyPair = await generateEcdhKeyPair();

    const { ciphertext } = await packEcdhDeviceEnvelope(
      vaultKey,
      deviceKeyPair.publicKey,
    );

    // Decode and check first byte is 0x04 (uncompressed point)
    const decoded = Uint8Array.from(atob(ciphertext), (c) => c.charCodeAt(0));
    expect(decoded[0]).toBe(0x04);
    expect(decoded.length).toBeGreaterThan(ECDH_PUBLIC_KEY_LENGTH);
  });

  it("produces different ciphertext each time (ephemeral keys)", async () => {
    const vaultKey = generateVaultKey();
    const deviceKeyPair = await generateEcdhKeyPair();

    const r1 = await packEcdhDeviceEnvelope(vaultKey, deviceKeyPair.publicKey);
    const r2 = await packEcdhDeviceEnvelope(vaultKey, deviceKeyPair.publicKey);

    expect(r1.ciphertext).not.toBe(r2.ciphertext);
  });
});
