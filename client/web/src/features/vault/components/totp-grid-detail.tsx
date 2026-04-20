import { useState, useCallback } from "react";
import { useTotpCode } from "@/features/vault/hooks/use-totp-code";
import { EntryIcon } from "./entry-icon";
import type { VaultEntry } from "@/types/vault-types";
import { Copy, Check } from "lucide-react";

interface TotpGridDetailProps {
  entry: VaultEntry;
}

export function TotpGridDetail({ entry }: TotpGridDetailProps) {
  const { code, timeLeft } = useTotpCode(entry.secret, entry.algorithm, entry.digits, entry.period);
  const [copied, setCopied] = useState(false);

  const handleCopy = useCallback(async () => {
    await navigator.clipboard.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }, [code]);

  return (
    <div className="border-border mb-4 flex flex-col items-center rounded-lg border py-6">
      <EntryIcon icon={entry.icon} issuer={entry.issuer} size="lg" />
      <p className="mt-2 text-sm font-semibold text-muted-foreground">{entry.issuer}</p>

      <div className="mt-3 flex items-baseline justify-center gap-3">
        <span className="font-mono text-2xl font-bold tracking-[0.15em] sm:text-4xl sm:tracking-widest">
          {code.slice(0, Math.ceil(code.length / 2))}
        </span>
        <span className="font-mono text-2xl font-bold tracking-[0.15em] sm:text-4xl sm:tracking-widest">
          {code.slice(Math.ceil(code.length / 2))}
        </span>
      </div>

      <div className="mt-2 flex items-center gap-2">
        <p className="text-muted-foreground text-sm">
          Your token expires in{" "}
          <span className={timeLeft <= 5 ? "text-destructive font-bold" : "font-bold"}>
            {timeLeft}
          </span>{" "}
          sec
        </p>
        <button
          onClick={handleCopy}
          className="text-muted-foreground hover:text-foreground p-2"
          title="Copy code"
        >
          {copied ? (
            <Check className="h-4 w-4 text-emerald-500 dark:text-emerald-400" />
          ) : (
            <Copy className="h-4 w-4" />
          )}
        </button>
      </div>
    </div>
  );
}
