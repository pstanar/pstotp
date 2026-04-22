import { aesGcmEncrypt, aesGcmDecrypt, toBase64, fromBase64 } from "@/lib/crypto";
import type { IconLibraryBlob } from "@/types/icon-library";

const NONCE_LENGTH = 12;

/**
 * Associated data for the library blob's AEAD. A fixed string per
 * blob-format version: changes the AD if we ever need to rotate the
 * blob schema incompatibly, so an old blob can't be rewrapped as a new
 * one without explicit migration.
 */
const ICON_LIBRARY_AD_V1 = new TextEncoder().encode("pstotp-icon-library-v1");

/**
 * Encrypt the library JSON with the user's vault key. Produces the
 * same nonce(12) || ciphertext+tag layout the vault-entry blob uses,
 * base64-encoded for the wire.
 */
export async function encryptIconLibrary(
  vaultKey: Uint8Array,
  blob: IconLibraryBlob,
): Promise<string> {
  const json = new TextEncoder().encode(JSON.stringify(blob));
  const { ciphertext, nonce } = await aesGcmEncrypt(vaultKey, json, ICON_LIBRARY_AD_V1);
  const packed = new Uint8Array(nonce.length + ciphertext.length);
  packed.set(nonce, 0);
  packed.set(ciphertext, nonce.length);
  return toBase64(packed);
}

/**
 * Decrypt a library blob fetched from the server. Throws on MAC failure
 * / wrong key — caller should handle by treating the library as empty
 * (with a warning) rather than silently dropping it.
 */
export async function decryptIconLibrary(
  vaultKey: Uint8Array,
  base64Payload: string,
): Promise<IconLibraryBlob> {
  const packed = fromBase64(base64Payload);
  const nonce = packed.slice(0, NONCE_LENGTH);
  const ciphertextWithTag = packed.slice(NONCE_LENGTH);
  const json = await aesGcmDecrypt(vaultKey, ciphertextWithTag, nonce, ICON_LIBRARY_AD_V1);
  return JSON.parse(new TextDecoder().decode(json)) as IconLibraryBlob;
}
