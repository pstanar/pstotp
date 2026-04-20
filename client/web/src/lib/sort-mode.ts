import type { VaultEntry } from "@/types/vault-types";
import { getUsageMap } from "./usage-tracker";

export type SortMode = "manual" | "alphabetical" | "lru" | "mfu";

const STORAGE_KEY = "pstotp:sort-mode";
const STORAGE_KEY_REVERSED = "pstotp:sort-reversed";

export function getSortMode(): SortMode {
  const value = localStorage.getItem(STORAGE_KEY);
  if (value === "alphabetical" || value === "lru" || value === "mfu") return value;
  return "manual";
}

export function setSortMode(mode: SortMode) {
  localStorage.setItem(STORAGE_KEY, mode);
}

export function getSortReversed(): boolean {
  return localStorage.getItem(STORAGE_KEY_REVERSED) === "true";
}

export function setSortReversed(reversed: boolean) {
  localStorage.setItem(STORAGE_KEY_REVERSED, String(reversed));
}

/**
 * Sort according to the mode's natural direction, then reverse if requested.
 * Reversal doesn't apply to MANUAL — that's the user's own order.
 */
export function sortEntries(
  entries: VaultEntry[],
  mode: SortMode,
  reversed: boolean = false,
): VaultEntry[] {
  if (mode === "manual") return entries;

  const copy = [...entries];
  if (mode === "alphabetical") {
    copy.sort((a, b) => {
      const byIssuer = a.issuer.localeCompare(b.issuer, undefined, { sensitivity: "base" });
      if (byIssuer !== 0) return byIssuer;
      return a.accountName.localeCompare(b.accountName, undefined, { sensitivity: "base" });
    });
  } else {
    const usage = getUsageMap();
    if (mode === "lru") {
      copy.sort((a, b) => (usage[b.id]?.lastUsedAt ?? 0) - (usage[a.id]?.lastUsedAt ?? 0));
    } else if (mode === "mfu") {
      copy.sort((a, b) => {
        const countDiff = (usage[b.id]?.useCount ?? 0) - (usage[a.id]?.useCount ?? 0);
        if (countDiff !== 0) return countDiff;
        return (usage[b.id]?.lastUsedAt ?? 0) - (usage[a.id]?.lastUsedAt ?? 0);
      });
    }
  }
  return reversed ? copy.reverse() : copy;
}
