const DB_NAME = "pstotp-device-keys";
const STORE_NAME = "keys";
const DB_VERSION = 1;

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      request.result.createObjectStore(STORE_NAME);
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

export async function saveDeviceKeyPair(
  deviceId: string,
  keyPair: CryptoKeyPair,
): Promise<void> {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, "readwrite");
    tx.objectStore(STORE_NAME).put(keyPair, deviceId);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

export async function loadDeviceKeyPair(
  deviceId: string,
): Promise<CryptoKeyPair | null> {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, "readonly");
    const request = tx.objectStore(STORE_NAME).get(deviceId);
    request.onsuccess = () => resolve(request.result ?? null);
    request.onerror = () => reject(request.error);
  });
}

export async function deleteDeviceKeyPair(
  deviceId: string,
): Promise<void> {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, "readwrite");
    tx.objectStore(STORE_NAME).delete(deviceId);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

const LOCAL_DEVICE_KEY = "local-device";

/** Load or create the browser's stable ECDH key pair. */
export async function getOrCreateLocalKeyPair(
  generateKeyPair: () => Promise<CryptoKeyPair>,
): Promise<CryptoKeyPair> {
  const existing = await loadDeviceKeyPair(LOCAL_DEVICE_KEY);
  if (existing) return existing;

  const keyPair = await generateKeyPair();
  await saveDeviceKeyPair(LOCAL_DEVICE_KEY, keyPair);
  return keyPair;
}
