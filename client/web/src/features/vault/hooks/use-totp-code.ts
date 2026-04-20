import { useMemo } from "react";
import { generateTotp } from "@/features/vault/utils/totp";
import { useTotpClock, getTimeLeft } from "./use-totp-clock";

export function useTotpCode(secret: string, algorithm: string, digits: number, period: number) {
  const epoch = useTotpClock();
  const timeLeft = getTimeLeft(epoch, period);
  const counter = Math.floor(epoch / period);
  const counterEpoch = counter * period;
  const code = useMemo(
    () => generateTotp(secret, algorithm, digits, period, counterEpoch),
    [secret, algorithm, digits, period, counterEpoch],
  );

  return { code, timeLeft };
}
