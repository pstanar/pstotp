import {
  packEcdhDeviceEnvelope,
  unpackEcdhDeviceEnvelope,
  aesGcmDecrypt,
  fromBase64,
} from "@/lib/crypto";
import { updateSelfEnvelope } from "@/features/devices/api/devices-api";
import { fetchVault } from "@/features/vault/api/vault-api";
import { decryptEntry } from "@/features/vault/utils/vault-crypto";
import { loadDeviceKeyPair } from "@/lib/device-key-store";
import type { Envelope } from "@/types/api-types";

/** Fetch vault entries and decrypt them with the given vault key. */
export async function fetchAndDecryptVault(vaultKey: Uint8Array) {
  const vaultResponse = await fetchVault();
  return Promise.all(
    vaultResponse.entries
      .filter((dto) => !dto.deletedAt)
      .map(async (dto) => {
        const plaintext = await decryptEntry(vaultKey, dto.entryPayload, dto.id);
        return { ...plaintext, id: dto.id, version: dto.entryVersion };
      }),
  );
}

/** Try to decrypt the device envelope using the stored ECDH key pair. Returns null on failure. */
export async function tryDecryptDeviceEnvelope(
  deviceId: string,
  envelope: Envelope,
): Promise<Uint8Array | null> {
  try {
    const storedKeyPair = await loadDeviceKeyPair(deviceId);
    if (!storedKeyPair) return null;
    return await unpackEcdhDeviceEnvelope(
      envelope.ciphertext,
      envelope.nonce,
      storedKeyPair.privateKey,
    );
  } catch {
    // Device key mismatch or format change — caller handles fallback
    return null;
  }
}

/** Decrypt the password envelope using a derived envelope key. */
export async function decryptPasswordEnvelope(
  envelopeKey: Uint8Array,
  envelope: Envelope,
): Promise<Uint8Array> {
  const ciphertext = fromBase64(envelope.ciphertext);
  const nonce = fromBase64(envelope.nonce);
  return aesGcmDecrypt(envelopeKey, ciphertext, nonce);
}

/** Re-wrap vaultKey with the current ECDH key and push to server. Fire-and-forget. */
export function rebuildDeviceEnvelope(vaultKey: Uint8Array, publicKey: CryptoKey) {
  void (async () => {
    try {
      const envelope = await packEcdhDeviceEnvelope(vaultKey, publicKey);
      await updateSelfEnvelope({ ciphertext: envelope.ciphertext, nonce: envelope.nonce, version: 1 });
    } catch {
      // Rebuild failed — will retry on next password login
    }
  })();
}
