import { useEffect, useRef } from "react";

const ACTIVITY_EVENTS: (keyof WindowEventMap)[] = [
  "mousedown", "mousemove", "keydown", "touchstart", "scroll", "click",
];

/**
 * Calls `onLock` after `timeoutMs` of inactivity.
 * Resets the timer on any user interaction.
 * Only active when `enabled` is true.
 */
export function useInactivityLock(
  onLock: () => void,
  timeoutMs: number,
  enabled: boolean,
) {
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const onLockRef = useRef(onLock);

  useEffect(() => {
    onLockRef.current = onLock;
  }, [onLock]);

  useEffect(() => {
    if (!enabled) return;

    const resetTimer = () => {
      if (timerRef.current) clearTimeout(timerRef.current);
      timerRef.current = setTimeout(() => onLockRef.current(), timeoutMs);
    };

    // Start the timer
    resetTimer();

    // Reset on any user activity
    for (const event of ACTIVITY_EVENTS) {
      window.addEventListener(event, resetTimer, { passive: true });
    }

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
      for (const event of ACTIVITY_EVENTS) {
        window.removeEventListener(event, resetTimer);
      }
    };
  }, [timeoutMs, enabled]);
}
