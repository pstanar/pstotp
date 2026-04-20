import { useLayoutEffect, type MutableRefObject } from "react";
import { useTotpCode } from "@/features/vault/hooks/use-totp-code";

interface TotpLiveDisplayProps {
  secret: string;
  algorithm: string;
  digits: number;
  period: number;
  /** Optional ref updated every render with the currently displayed code, so
   *  the parent can copy exactly what the user sees (avoids a race where a
   *  late click near a period boundary would copy the next code). */
  codeRef?: MutableRefObject<string>;
}

/**
 * Renders the live-updating TOTP code and countdown seconds in isolation.
 * Extracted so that the 1 Hz clock tick only causes this small subtree to
 * re-render, not the entire TotpCard (icon, issuer, buttons, etc).
 */
export function TotpLiveDisplay({ secret, algorithm, digits, period, codeRef }: TotpLiveDisplayProps) {
  const { code, timeLeft } = useTotpCode(secret, algorithm, digits, period);
  // useLayoutEffect (vs useEffect) runs synchronously after DOM mutation,
  // before the browser paints. That keeps the "copy exactly what's on
  // screen" guarantee — a click right after a period boundary still sees
  // the code the user actually saw.
  useLayoutEffect(() => {
    if (codeRef) codeRef.current = code;
  }, [code, codeRef]);
  const mid = Math.ceil(code.length / 2);
  return (
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
  );
}
