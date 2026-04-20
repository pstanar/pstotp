import { useSyncExternalStore } from "react";

let currentEpoch = Math.floor(Date.now() / 1000);
const listeners = new Set<() => void>();

// Single global interval — ticks once per second
setInterval(() => {
  const now = Math.floor(Date.now() / 1000);
  if (now !== currentEpoch) {
    currentEpoch = now;
    for (const listener of listeners) listener();
  }
}, 200); // Check 5x/sec for accuracy, only notifies on second change

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function getSnapshot() {
  return currentEpoch;
}

/** Returns the current epoch second, updates once per second via a single shared timer. */
export function useTotpClock(): number {
  return useSyncExternalStore(subscribe, getSnapshot);
}

/** Derive timeLeft from epoch and period. */
export function getTimeLeft(epoch: number, period: number): number {
  return period - (epoch % period);
}
