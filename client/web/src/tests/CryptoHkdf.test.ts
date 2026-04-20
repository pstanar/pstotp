import { describe, it, expect } from "vitest";
import {
  derivePasswordVerifier,
  derivePasswordEnvelopeKey,
  deriveRecoveryUnlockKey,
  generateVaultKey,
} from "@/lib/crypto";

describe("HKDF-SHA256 derivation", () => {
  it("derivePasswordVerifier produces 32 bytes", async () => {
    const ikm = generateVaultKey();
    const result = await derivePasswordVerifier(ikm);
    expect(result.length).toBe(32);
  });

  it("derivePasswordEnvelopeKey produces 32 bytes", async () => {
    const ikm = generateVaultKey();
    const result = await derivePasswordEnvelopeKey(ikm);
    expect(result.length).toBe(32);
  });

  it("deriveRecoveryUnlockKey produces 32 bytes", async () => {
    const ikm = generateVaultKey();
    const result = await deriveRecoveryUnlockKey(ikm);
    expect(result.length).toBe(32);
  });

  it("same input produces same output (deterministic)", async () => {
    const ikm = generateVaultKey();
    const r1 = await derivePasswordVerifier(ikm);
    const r2 = await derivePasswordVerifier(ikm);
    expect(Array.from(r1)).toEqual(Array.from(r2));
  });

  it("different contexts produce different keys", async () => {
    const ikm = generateVaultKey();
    const verifier = await derivePasswordVerifier(ikm);
    const envelopeKey = await derivePasswordEnvelopeKey(ikm);
    expect(Array.from(verifier)).not.toEqual(Array.from(envelopeKey));
  });

  it("different inputs produce different keys", async () => {
    const ikm1 = generateVaultKey();
    const ikm2 = generateVaultKey();
    const r1 = await derivePasswordVerifier(ikm1);
    const r2 = await derivePasswordVerifier(ikm2);
    expect(Array.from(r1)).not.toEqual(Array.from(r2));
  });
});
