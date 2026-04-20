import { describe, it, expect, afterEach } from "vitest";
import { useVaultStore } from "@/stores/useVaultStore";
import { useAuthStore } from "@/stores/useAuthStore";
import { generateVaultKey } from "@/lib/crypto";

afterEach(() => {
  useVaultStore.getState().lock();
  useAuthStore.getState().logout();
});

describe("WebLockNowAction", () => {
  it("vault starts unlocked after setVaultKey + unlock", () => {
    const key = generateVaultKey();
    useVaultStore.getState().setVaultKey(key);
    useVaultStore.getState().unlock([{
      id: "1", version: 1, issuer: "Test", accountName: "user",
      secret: "ABC", algorithm: "SHA1", digits: 6, period: 30,
    }]);

    expect(useVaultStore.getState().isUnlocked).toBe(true);
    expect(useVaultStore.getState().entries).toHaveLength(1);
  });

  it("clears vault entries and zeros key on lock", () => {
    const key = generateVaultKey();
    useVaultStore.getState().setVaultKey(key);
    useVaultStore.getState().unlock([{
      id: "1", version: 1, issuer: "Test", accountName: "user",
      secret: "ABC", algorithm: "SHA1", digits: 6, period: 30,
    }]);

    useVaultStore.getState().lock();

    const state = useVaultStore.getState();
    expect(state.isUnlocked).toBe(false);
    expect(state.entries).toHaveLength(0);
    expect(state.vaultKey).toBeNull();
    // Key bytes zeroed
    expect(key.every((b) => b === 0)).toBe(true);
  });

  it("requires re-unlock before entries are accessible again", () => {
    useVaultStore.getState().unlock([{
      id: "1", version: 1, issuer: "Test", accountName: "user",
      secret: "ABC", algorithm: "SHA1", digits: 6, period: 30,
    }]);

    useVaultStore.getState().lock();

    // After lock, entries are gone — need to unlock again
    expect(useVaultStore.getState().isUnlocked).toBe(false);
    expect(useVaultStore.getState().entries).toHaveLength(0);

    // Re-unlock with new entries
    useVaultStore.getState().unlock([{
      id: "2", version: 1, issuer: "New", accountName: "new",
      secret: "DEF", algorithm: "SHA1", digits: 6, period: 30,
    }]);
    expect(useVaultStore.getState().isUnlocked).toBe(true);
    expect(useVaultStore.getState().entries).toHaveLength(1);
    expect(useVaultStore.getState().entries[0].issuer).toBe("New");
  });
});
