import { create } from "zustand";
import type { VaultEntry } from "@/types/vault-types";
import { useIconLibraryStore } from "./useIconLibraryStore";

interface VaultState {
  isUnlocked: boolean;
  vaultKey: Uint8Array | null;
  entries: VaultEntry[];
  lastSyncAt: string | null;
}

interface VaultActions {
  setVaultKey: (key: Uint8Array) => void;
  unlock: (entries: VaultEntry[]) => void;
  lock: () => void;
  setEntries: (entries: VaultEntry[]) => void;
  addEntry: (entry: VaultEntry) => void;
  updateEntry: (id: string, entry: Partial<VaultEntry>) => void;
  removeEntry: (id: string) => void;
}

interface VaultStore extends VaultState, VaultActions {}

const initialState: VaultState = {
  isUnlocked: false,
  vaultKey: null,
  entries: [],
  lastSyncAt: null,
};

export const useVaultStore = create<VaultStore>()((set, get) => ({
  ...initialState,
  setVaultKey: (key) => set({ vaultKey: key }),
  unlock: (entries) =>
    set({
      isUnlocked: true,
      entries,
      lastSyncAt: new Date().toISOString(),
    }),
  lock: () => {
    // Zero out vault key before clearing
    const { vaultKey } = get();
    if (vaultKey) vaultKey.fill(0);
    // Drop any cached icon-library state too — it was keyed by this vault key.
    useIconLibraryStore.getState().clear();
    set(initialState);
  },
  setEntries: (entries) =>
    set({ entries, lastSyncAt: new Date().toISOString() }),
  addEntry: (entry) =>
    set((state) => ({ entries: [...state.entries, entry] })),
  updateEntry: (id, updates) =>
    set((state) => ({
      entries: state.entries.map((e) =>
        e.id === id ? { ...e, ...updates } : e,
      ),
    })),
  removeEntry: (id) =>
    set((state) => ({
      entries: state.entries.filter((e) => e.id !== id),
    })),
}));
