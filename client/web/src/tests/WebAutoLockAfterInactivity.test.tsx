import { describe, it, expect, vi, afterEach } from "vitest";
import { useVaultStore } from "@/stores/useVaultStore";
import { generateVaultKey } from "@/lib/crypto";

afterEach(() => {
  useVaultStore.getState().lock();
  vi.restoreAllMocks();
});

describe("WebAutoLockAfterInactivity", () => {
  it("lock clears vault entries and zeros key (simulating inactivity timeout)", () => {
    const key = generateVaultKey();
    useVaultStore.getState().setVaultKey(key);
    useVaultStore.getState().unlock([{
      id: "1", version: 1, issuer: "Test", accountName: "user",
      secret: "ABC", algorithm: "SHA1", digits: 6, period: 30,
    }]);

    expect(useVaultStore.getState().isUnlocked).toBe(true);
    expect(useVaultStore.getState().entries).toHaveLength(1);

    // Simulate what the inactivity hook does: call lock()
    useVaultStore.getState().lock();

    expect(useVaultStore.getState().isUnlocked).toBe(false);
    expect(useVaultStore.getState().entries).toHaveLength(0);
    expect(useVaultStore.getState().vaultKey).toBeNull();
  });

  it("clears decrypted entries from memory on lock", () => {
    const key = generateVaultKey();
    useVaultStore.getState().setVaultKey(key);
    useVaultStore.getState().unlock([
      { id: "1", version: 1, issuer: "A", accountName: "a", secret: "SEC1", algorithm: "SHA1", digits: 6, period: 30 },
      { id: "2", version: 1, issuer: "B", accountName: "b", secret: "SEC2", algorithm: "SHA1", digits: 6, period: 30 },
    ]);

    useVaultStore.getState().lock();

    // Entries array should be empty — no trace of secrets
    const state = useVaultStore.getState();
    expect(state.entries).toHaveLength(0);
    expect(state.vaultKey).toBeNull();
    // Original key bytes should be zeroed
    expect(key.every((b) => b === 0)).toBe(true);
  });

  it("vault key is zeroed on lock to prevent memory extraction", () => {
    const key = generateVaultKey();
    const keySnapshot = new Uint8Array(key); // copy before lock
    useVaultStore.getState().setVaultKey(key);
    useVaultStore.getState().unlock([]);

    useVaultStore.getState().lock();

    // The original key buffer should be all zeros
    expect(key.every((b) => b === 0)).toBe(true);
    // But the snapshot we took before should still have the original values
    expect(keySnapshot.some((b) => b !== 0)).toBe(true);
  });
});
