import { argon2id } from "hash-wasm";
import type { KdfConfig } from "@/types/api-types";

// --- Base64 helpers (standard base64, matching .NET Convert.ToBase64String) ---

export function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}

export function fromBase64(str: string): Uint8Array {
  const binary = atob(str);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

// --- Random generation ---

export function generateRandomBytes(length: number): Uint8Array {
  return crypto.getRandomValues(new Uint8Array(length));
}

export function generateSalt(): Uint8Array {
  return generateRandomBytes(16);
}

export function generateVaultKey(): Uint8Array {
  return generateRandomBytes(32);
}

// --- Argon2id (via hash-wasm WASM) ---

export async function derivePasswordAuthKey(
  password: string,
  salt: Uint8Array,
  kdfConfig: KdfConfig,
): Promise<Uint8Array> {
  const hash = await argon2id({
    password,
    salt,
    memorySize: kdfConfig.memoryMb * 1024, // MB to KB
    iterations: kdfConfig.iterations,
    parallelism: kdfConfig.parallelism,
    hashLength: 32,
    outputType: "binary",
  });
  return new Uint8Array(hash);
}

// --- HKDF-SHA256 (Web Crypto) ---

async function hkdfDerive(
  ikm: Uint8Array,
  info: string,
  length: number = 32,
): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey("raw", ikm as BufferSource, "HKDF", false, [
    "deriveBits",
  ]);
  const bits = await crypto.subtle.deriveBits(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: new Uint8Array(0), // Backend HkdfHelper passes no salt
      info: new TextEncoder().encode(info),
    },
    key,
    length * 8,
  );
  return new Uint8Array(bits);
}

export function derivePasswordVerifier(
  passwordAuthKey: Uint8Array,
): Promise<Uint8Array> {
  return hkdfDerive(passwordAuthKey, "auth-verifier-v1");
}

export function derivePasswordEnvelopeKey(
  passwordAuthKey: Uint8Array,
): Promise<Uint8Array> {
  return hkdfDerive(passwordAuthKey, "vault-password-envelope-v1");
}

export function deriveRecoveryUnlockKey(
  recoverySeed: Uint8Array,
): Promise<Uint8Array> {
  return hkdfDerive(recoverySeed, "totp-vault-recovery-unlock-v1");
}

// --- HMAC-SHA256 (Web Crypto) ---

export async function computeClientProof(
  verifier: Uint8Array,
  nonce: Uint8Array,
  loginSessionId: string,
): Promise<Uint8Array> {
  const sessionIdBytes = guidToBytes(loginSessionId);

  // message = nonce || sessionIdBytes
  const message = new Uint8Array(nonce.length + sessionIdBytes.length);
  message.set(nonce, 0);
  message.set(sessionIdBytes, nonce.length);

  const key = await crypto.subtle.importKey(
    "raw",
    verifier as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, message as BufferSource);
  return new Uint8Array(signature);
}

// --- AES-256-GCM (Web Crypto) ---

export async function aesGcmEncrypt(
  key: Uint8Array,
  plaintext: Uint8Array,
  associatedData?: Uint8Array,
): Promise<{ ciphertext: Uint8Array; nonce: Uint8Array }> {
  const nonce = generateRandomBytes(12);
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key as BufferSource,
    "AES-GCM",
    false,
    ["encrypt"],
  );
  // Web Crypto appends the 16-byte tag to the ciphertext
  const params: AesGcmParams = { name: "AES-GCM", iv: nonce as BufferSource };
  if (associatedData) params.additionalData = associatedData as BufferSource;
  const encrypted = await crypto.subtle.encrypt(
    params,
    cryptoKey,
    plaintext as BufferSource,
  );
  return { ciphertext: new Uint8Array(encrypted), nonce };
}

export async function aesGcmDecrypt(
  key: Uint8Array,
  ciphertext: Uint8Array,
  nonce: Uint8Array,
  associatedData?: Uint8Array,
): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key as BufferSource,
    "AES-GCM",
    false,
    ["decrypt"],
  );
  const params: AesGcmParams = { name: "AES-GCM", iv: nonce as BufferSource };
  if (associatedData) params.additionalData = associatedData as BufferSource;
  const decrypted = await crypto.subtle.decrypt(
    params,
    cryptoKey,
    ciphertext as BufferSource,
  );
  return new Uint8Array(decrypted);
}

// --- GUID to bytes (.NET mixed-endian format) ---
// .NET Guid.ToByteArray() layout:
//   [4 bytes LE] [2 bytes LE] [2 bytes LE] [2 bytes BE] [6 bytes BE]
// Example: "aabbccdd-eeff-0011-2233-445566778899"
//   → [dd,cc,bb,aa, ff,ee, 11,00, 22,33, 44,55,66,77,88,99]

export function guidToBytes(guid: string): Uint8Array {
  const hex = guid.replace(/-/g, "");
  if (hex.length !== 32) throw new Error(`Invalid GUID: ${guid}`);

  const bytes = new Uint8Array(16);
  for (let i = 0; i < 16; i++) {
    bytes[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
  }

  // Reverse first 4 bytes (little-endian)
  const t0 = bytes[0]; bytes[0] = bytes[3]; bytes[3] = t0;
  const t1 = bytes[1]; bytes[1] = bytes[2]; bytes[2] = t1;
  // Reverse bytes 4-5 (little-endian)
  const t4 = bytes[4]; bytes[4] = bytes[5]; bytes[5] = t4;
  // Reverse bytes 6-7 (little-endian)
  const t6 = bytes[6]; bytes[6] = bytes[7]; bytes[7] = t6;
  // Bytes 8-15 stay big-endian (as-is)

  return bytes;
}

// --- Recovery code generation ---

export function generateRecoveryCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // No I/O/0/1 to avoid confusion
  const bytes = generateRandomBytes(10);
  let code = "";
  // Bitmask instead of modulo: `b % n` on a crypto byte produces biased results
  // unless 256 is divisible by n. The bitmask `b & (n-1)` is unbiased when n is
  // a power of 2 — chars.length must stay 32 (2^5) for this to hold.
  for (const b of bytes) code += chars[b & (chars.length - 1)];
  return code;
}

export async function hashRecoveryCode(
  code: string,
  salt: Uint8Array,
): Promise<string> {
  const hash = await argon2id({
    password: code,
    salt,
    memorySize: 64 * 1024, // 64 MB in KB
    iterations: 3,
    parallelism: 4,
    hashLength: 32,
    outputType: "binary",
  });
  return toBase64(new Uint8Array(hash));
}

// --- ECDH P-256 (Web Crypto) ---

const ECDH_CURVE = "P-256";
const DEVICE_ENVELOPE_CONTEXT = "device-envelope-v1";
export const ECDH_PUBLIC_KEY_LENGTH = 65; // Uncompressed P-256 point

export async function generateEcdhKeyPair(): Promise<CryptoKeyPair> {
  return crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: ECDH_CURVE },
    false, // non-extractable private key (for IndexedDB storage)
    ["deriveKey", "deriveBits"],
  );
}

export async function exportEcdhPublicKey(key: CryptoKey): Promise<Uint8Array> {
  const raw = await crypto.subtle.exportKey("raw", key);
  return new Uint8Array(raw);
}

export async function importEcdhPublicKey(bytes: Uint8Array): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    bytes as BufferSource,
    { name: "ECDH", namedCurve: ECDH_CURVE },
    true,
    [],
  );
}

export async function deriveEcdhWrappingKey(
  privateKey: CryptoKey,
  publicKey: CryptoKey,
): Promise<Uint8Array> {
  // ECDH → raw shared secret
  const sharedBits = await crypto.subtle.deriveBits(
    { name: "ECDH", public: publicKey },
    privateKey,
    256,
  );
  // HKDF-SHA256 to derive a 32-byte AES wrapping key
  const hkdfKey = await crypto.subtle.importKey(
    "raw",
    sharedBits,
    "HKDF",
    false,
    ["deriveBits"],
  );
  const derived = await crypto.subtle.deriveBits(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: new Uint8Array(0),
      info: new TextEncoder().encode(DEVICE_ENVELOPE_CONTEXT),
    },
    hkdfKey,
    256,
  );
  return new Uint8Array(derived);
}

/** Pack an ECDH device envelope: ephemeralPublicKey(65) || nonce(12) || ciphertext+tag */
export async function packEcdhDeviceEnvelope(
  vaultKey: Uint8Array,
  recipientPublicKey: CryptoKey,
): Promise<{ ciphertext: string; nonce: string }> {
  // Generate ephemeral key pair
  const ephemeral = await generateEcdhKeyPair();
  const ephemeralPub = await exportEcdhPublicKey(ephemeral.publicKey);

  // Derive wrapping key
  const wrappingKey = await deriveEcdhWrappingKey(ephemeral.privateKey, recipientPublicKey);

  // Encrypt VaultKey
  const { ciphertext, nonce } = await aesGcmEncrypt(wrappingKey, vaultKey);

  // Pack ephemeral public key into ciphertext field
  const packed = new Uint8Array(ephemeralPub.length + ciphertext.length);
  packed.set(ephemeralPub, 0);
  packed.set(ciphertext, ephemeralPub.length);

  return {
    ciphertext: toBase64(packed),
    nonce: toBase64(nonce),
  };
}

/** Unpack an ECDH device envelope and decrypt VaultKey */
export async function unpackEcdhDeviceEnvelope(
  ciphertextBase64: string,
  nonceBase64: string,
  devicePrivateKey: CryptoKey,
): Promise<Uint8Array> {
  const packed = fromBase64(ciphertextBase64);
  const nonce = fromBase64(nonceBase64);

  // Split: ephemeral public key || actual ciphertext+tag
  const ephemeralPub = packed.slice(0, ECDH_PUBLIC_KEY_LENGTH);
  const ciphertext = packed.slice(ECDH_PUBLIC_KEY_LENGTH);

  // Import ephemeral public key and derive wrapping key
  const ephemeralKey = await importEcdhPublicKey(ephemeralPub);
  const wrappingKey = await deriveEcdhWrappingKey(devicePrivateKey, ephemeralKey);

  // Decrypt VaultKey
  return aesGcmDecrypt(wrappingKey, ciphertext, nonce);
}
