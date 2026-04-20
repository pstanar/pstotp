const STORAGE_KEY = "pstotp:entry-usage";

export interface EntryUsage {
  lastUsedAt: number;
  useCount: number;
}

type UsageMap = Record<string, EntryUsage>;

function load(): UsageMap {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

function save(map: UsageMap) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(map));
}

export function recordUse(entryId: string) {
  const map = load();
  const prev = map[entryId] ?? { lastUsedAt: 0, useCount: 0 };
  map[entryId] = { lastUsedAt: Date.now(), useCount: prev.useCount + 1 };
  save(map);
}

export function getUsageMap(): UsageMap {
  return load();
}

export function forgetEntry(entryId: string) {
  const map = load();
  if (entryId in map) {
    delete map[entryId];
    save(map);
  }
}
