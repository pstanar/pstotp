import type { DeviceDto } from "@/types/api-types";
import { generateEcdhKeyPair, exportEcdhPublicKey, toBase64 } from "@/lib/crypto";
import { getOrCreateLocalKeyPair } from "@/lib/device-key-store";

export interface DeviceInfoWithKeyPair {
  device: DeviceDto;
  keyPair: CryptoKeyPair;
}

export async function getDeviceInfoWithKeyPair(): Promise<DeviceInfoWithKeyPair> {
  const ua = navigator.userAgent;

  let browser = "Unknown Browser";
  if (ua.includes("Firefox/")) browser = "Firefox";
  else if (ua.includes("Edg/")) browser = "Edge";
  else if (ua.includes("Chrome/")) browser = "Chrome";
  else if (ua.includes("Safari/")) browser = "Safari";

  let os = "Unknown OS";
  if (ua.includes("Windows")) os = "Windows";
  else if (ua.includes("Mac OS")) os = "macOS";
  else if (ua.includes("Linux")) os = "Linux";
  else if (ua.includes("Android")) os = "Android";
  else if (ua.includes("iPhone") || ua.includes("iPad")) os = "iOS";

  // Reuse the browser's stable ECDH key pair (persisted in IndexedDB)
  const keyPair = await getOrCreateLocalKeyPair(generateEcdhKeyPair);
  const publicKeyBytes = await exportEcdhPublicKey(keyPair.publicKey);

  return {
    device: {
      deviceName: `${browser} on ${os}`,
      platform: os.toLowerCase(),
      clientType: "web",
      devicePublicKey: toBase64(publicKeyBytes),
    },
    keyPair,
  };
}
