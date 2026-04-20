import { describe, it, expect, afterEach } from "vitest";
import { useVaultStore } from "@/stores/useVaultStore";
import { generateVaultKey } from "@/lib/crypto";
import type { VaultEntry } from "@/types/vault-types";

const testEntry: VaultEntry = {
  id: "entry-1",
  version: 1,
  issuer: "TestService",
  accountName: "user@test.com",
  secret: "JBSWY3DPEHPK3PXP",
  algorithm: "SHA1",
  digits: 6,
  period: 30,
};

afterEach(() => {
  useVaultStore.getState().lock();
});

describe("UnlockVault", () => {
  it("starts in locked state", () => {
    const { isUnlocked, entries, vaultKey } = useVaultStore.getState();
    expect(isUnlocked).toBe(false);
    expect(entries).toHaveLength(0);
    expect(vaultKey).toBeNull();
  });

  it("transitions to unlocked state with entries", () => {
    const key = generateVaultKey();
    useVaultStore.getState().setVaultKey(key);
    useVaultStore.getState().unlock([testEntry]);

    const state = useVaultStore.getState();
    expect(state.isUnlocked).toBe(true);
    expect(state.entries).toHaveLength(1);
    expect(state.entries[0].issuer).toBe("TestService");
    expect(state.vaultKey).toBe(key);
  });

  it("clears entries and zeros vault key on lock", () => {
    const key = generateVaultKey();
    useVaultStore.getState().setVaultKey(key);
    useVaultStore.getState().unlock([testEntry]);

    useVaultStore.getState().lock();

    const state = useVaultStore.getState();
    expect(state.isUnlocked).toBe(false);
    expect(state.entries).toHaveLength(0);
    expect(state.vaultKey).toBeNull();
    // Original key bytes should be zeroed
    expect(key.every((b) => b === 0)).toBe(true);
  });

  it("supports multiple entries on unlock", () => {
    const entry2: VaultEntry = { ...testEntry, id: "entry-2", issuer: "Other" };
    useVaultStore.getState().unlock([testEntry, entry2]);

    expect(useVaultStore.getState().entries).toHaveLength(2);
  });
});
