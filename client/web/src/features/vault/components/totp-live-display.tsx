import { useLayoutEffect, type MutableRefObject } from "react";
import { useTotpCode } from "@/features/vault/hooks/use-totp-code";

export interface TotpLiveState {
  code: string;
  nextCode: string;
  timeLeft: number;
}

interface TotpLiveDisplayProps {
  secret: string;
  algorithm: string;
  digits: number;
  period: number;
  /** Optional ref kept in sync with what's currently rendered, so a parent
   *  can copy exactly what the user sees (including the handoff to the
   *  next code in the final 3s, when enabled). */
  liveRef?: MutableRefObject<TotpLiveState>;
  /** When true, render a faded preview of the next code during the last
   *  10 seconds. Purely visual — the copy-handoff lives in the parent. */
  showNextCode?: boolean;
}

/**
 * Renders the live-updating TOTP code and countdown seconds in isolation.
 * Extracted so that the 1 Hz clock tick only causes this small subtree to
 * re-render, not the entire TotpCard (icon, issuer, buttons, etc).
 */
export function TotpLiveDisplay({
  secret,
  algorithm,
  digits,
  period,
  liveRef,
  showNextCode,
}: TotpLiveDisplayProps) {
  const { code, nextCode, timeLeft } = useTotpCode(secret, algorithm, digits, period);
  // useLayoutEffect (vs useEffect) runs synchronously after DOM mutation,
  // before the browser paints. That keeps the "copy exactly what's on
  // screen" guarantee — a click right after a period boundary still sees
  // the code the user actually saw.
  useLayoutEffect(() => {
    if (liveRef) liveRef.current = { code, nextCode, timeLeft };
  }, [code, nextCode, timeLeft, liveRef]);
  const mid = Math.ceil(code.length / 2);
  const previewVisible = Boolean(showNextCode) && timeLeft <= 10 && nextCode.length > 0;
  const nextMid = nextCode.length > 0 ? Math.ceil(nextCode.length / 2) : 0;
  return (
    <div className="flex flex-col items-end">
      <div className="flex items-baseline gap-2">
        <span className="font-mono text-lg font-bold tracking-[0.12em] sm:text-2xl sm:tracking-[0.2em]">
          {code.slice(0, mid)}
        </span>
        <span className="font-mono text-lg font-bold tracking-[0.12em] sm:text-2xl sm:tracking-[0.2em]">
          {code.slice(mid)}
        </span>
        <span
          className={`w-6 text-xs font-medium tabular-nums ${
            timeLeft <= 10 ? (timeLeft <= 5 ? "text-destructive" : "text-muted-foreground") : "invisible"
          }`}
        >
          {timeLeft}s
        </span>
      </div>
      {previewVisible && (
        <div className="mt-0.5 flex items-baseline gap-1.5 text-muted-foreground/70">
          <span className="text-[10px] uppercase tracking-wider">next</span>
          <span className="font-mono text-xs font-medium tracking-[0.1em]">
            {nextCode.slice(0, nextMid)}
          </span>
          <span className="font-mono text-xs font-medium tracking-[0.1em]">
            {nextCode.slice(nextMid)}
          </span>
        </div>
      )}
    </div>
  );
}
