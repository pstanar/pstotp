import { create } from "zustand";
import { persist, createJSONStorage } from "zustand/middleware";

/**
 * Auto-lock timeout options. "Never" is represented as 0 so the consumer
 * can disable the inactivity timer without a special sentinel check.
 */
export const LOCK_TIMEOUT_OPTIONS: { label: string; ms: number }[] = [
  { label: "1 minute", ms: 60_000 },
  { label: "5 minutes", ms: 5 * 60_000 },
  { label: "15 minutes", ms: 15 * 60_000 },
  { label: "1 hour", ms: 60 * 60_000 },
  { label: "Never", ms: 0 },
];

export const DEFAULT_LOCK_TIMEOUT_MS = 5 * 60_000;

interface SettingsStore {
  lockTimeoutMs: number;
  setLockTimeoutMs: (ms: number) => void;
  // When true, show a faded preview of the next TOTP code during the
  // final 10s and hand out that next code on copy during the final 3s.
  // Off by default; matches the Android client's "Show upcoming code".
  showNextCode: boolean;
  setShowNextCode: (v: boolean) => void;
}

export const useSettingsStore = create<SettingsStore>()(
  persist(
    (set) => ({
      lockTimeoutMs: DEFAULT_LOCK_TIMEOUT_MS,
      setLockTimeoutMs: (ms) => set({ lockTimeoutMs: ms }),
      showNextCode: false,
      setShowNextCode: (v) => set({ showNextCode: v }),
    }),
    {
      name: "pstotp-settings",
      storage: createJSONStorage(() => localStorage),
    },
  ),
);
