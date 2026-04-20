import {
  aesGcmEncrypt,
  aesGcmDecrypt,
  toBase64,
  fromBase64,
} from "@/lib/crypto";
import type { VaultEntryPlaintext } from "@/types/vault-types";

const NONCE_LENGTH = 12;

/**
 * Encrypt a vault entry plaintext to a base64 payload for the server.
 * Matches backend VaultCrypto.EncryptEntry: nonce(12) || ciphertext || tag(16)
 * Associated data: entry ID as UTF-8 string.
 */
export async function encryptEntry(
  vaultKey: Uint8Array,
  plaintext: VaultEntryPlaintext,
  entryId: string,
): Promise<string> {
  const json = new TextEncoder().encode(JSON.stringify(plaintext));
  const ad = new TextEncoder().encode(entryId);
  const { ciphertext, nonce } = await aesGcmEncrypt(vaultKey, json, ad);

  // Pack: nonce || ciphertext (which already includes tag from Web Crypto)
  const packed = new Uint8Array(nonce.length + ciphertext.length);
  packed.set(nonce, 0);
  packed.set(ciphertext, nonce.length);

  return toBase64(packed);
}

/**
 * Decrypt a base64 payload from the server to a vault entry plaintext.
 * Matches backend VaultCrypto.DecryptEntry.
 */
export async function decryptEntry(
  vaultKey: Uint8Array,
  base64Payload: string,
  entryId: string,
): Promise<VaultEntryPlaintext> {
  const packed = fromBase64(base64Payload);
  const nonce = packed.slice(0, NONCE_LENGTH);
  const ciphertextWithTag = packed.slice(NONCE_LENGTH);
  const ad = new TextEncoder().encode(entryId);

  const json = await aesGcmDecrypt(vaultKey, ciphertextWithTag, nonce, ad);
  return JSON.parse(new TextDecoder().decode(json)) as VaultEntryPlaintext;
}
