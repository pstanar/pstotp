import { useMemo } from "react";
import { generateTotp } from "@/features/vault/utils/totp";
import { useTotpClock, getTimeLeft } from "./use-totp-clock";

export function useTotpCode(secret: string, algorithm: string, digits: number, period: number) {
  const epoch = useTotpClock();
  const timeLeft = getTimeLeft(epoch, period);
  const counter = Math.floor(epoch / period);
  const counterEpoch = counter * period;
  const nextCounterEpoch = counterEpoch + period;
  const code = useMemo(
    () => generateTotp(secret, algorithm, digits, period, counterEpoch),
    [secret, algorithm, digits, period, counterEpoch],
  );
  // Next step's code — used by the optional preview + copy-handoff when the
  // current code is about to expire. Cheap to compute and memo'd against
  // the next counter boundary, so it only rebuilds at period rollover.
  const nextCode = useMemo(
    () => generateTotp(secret, algorithm, digits, period, nextCounterEpoch),
    [secret, algorithm, digits, period, nextCounterEpoch],
  );

  return { code, nextCode, timeLeft };
}
