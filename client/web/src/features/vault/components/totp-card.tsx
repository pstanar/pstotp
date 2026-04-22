import { useState, useCallback, useRef } from "react";
import { useToast } from "@/hooks/use-toast";
import { useSettingsStore } from "@/stores/useSettingsStore";
import { generateTotp } from "@/features/vault/utils/totp";
import { buildOtpauthUri } from "@/features/vault/utils/otpauth-uri";
import { EntryIcon } from "./entry-icon";
import { CountdownRing } from "./countdown-ring";
import { TotpLiveDisplay, type TotpLiveState } from "./totp-live-display";
import { EntryContextMenu } from "./entry-context-menu";
import { QrCodeDialog } from "./qr-code-dialog";
import { recordUse } from "@/lib/usage-tracker";
import type { VaultEntry } from "@/types/vault-types";
import { Copy, Check, MoreVertical } from "lucide-react";

interface TotpCardProps {
  entry: VaultEntry;
  onEdit: () => void;
  onDelete: () => void;
}

export function TotpCard({ entry, onEdit, onDelete }: TotpCardProps) {
  const [copied, setCopied] = useState(false);
  const [menuPos, setMenuPos] = useState<{ x: number; y: number } | null>(null);
  const [showQr, setShowQr] = useState(false);
  const { toast } = useToast();
  const showNextCode = useSettingsStore((s) => s.showNextCode);
  // Always copy whatever TotpLiveDisplay currently shows. Falling back to a
  // fresh generateTotp only for the very first click before the display has
  // rendered (unlikely in practice).
  const liveRef = useRef<TotpLiveState>({ code: "", nextCode: "", timeLeft: 0 });

  const handleCopyCode = useCallback(async () => {
    const state = liveRef.current;
    const useNext = showNextCode && state.timeLeft <= 3 && state.nextCode.length > 0;
    const code = useNext
      ? state.nextCode
      : state.code || generateTotp(entry.secret, entry.algorithm, entry.digits, entry.period);
    await navigator.clipboard.writeText(code);
    recordUse(entry.id);
    setCopied(true);
    toast(useNext ? "Next code copied" : "Code copied");
    setTimeout(() => setCopied(false), 2000);
  }, [entry.secret, entry.algorithm, entry.digits, entry.period, entry.id, toast, showNextCode]);

  const handleCopySecret = useCallback(async () => {
    await navigator.clipboard.writeText(entry.secret);
    toast("Secret key copied");
  }, [entry.secret, toast]);

  const handleContextMenu = (e: React.MouseEvent) => {
    e.preventDefault();
    setMenuPos({ x: e.clientX, y: e.clientY });
  };

  const handleMenuButton = (e: React.MouseEvent) => {
    const rect = e.currentTarget.getBoundingClientRect();
    setMenuPos({ x: rect.right, y: rect.bottom + 4 });
  };

  return (
    <>
      <div
        className="border-border rounded-lg border bg-card p-4 shadow-sm transition-all duration-150 hover:shadow-md select-none"
        onContextMenu={handleContextMenu}
      >
        <div className="flex items-center gap-3">
          <div className="shrink-0">
            <CountdownRing period={entry.period} size={44} radius={20}>
              <EntryIcon icon={entry.icon} issuer={entry.issuer} />
            </CountdownRing>
          </div>

          <div className="min-w-0 flex-1">
            <p className="text-lg font-medium truncate leading-tight text-muted-foreground">{entry.issuer}</p>
          </div>

          <TotpLiveDisplay
            secret={entry.secret}
            algorithm={entry.algorithm}
            digits={entry.digits}
            period={entry.period}
            liveRef={liveRef}
            showNextCode={showNextCode}
          />

          <button onClick={handleCopyCode}
            className="text-muted-foreground hover:text-foreground rounded-md p-2.5 transition-colors hover:bg-accent"
            title="Copy code">
            {copied ? <Check className="h-4 w-4 text-emerald-500 dark:text-emerald-400" /> : <Copy className="h-4 w-4" />}
          </button>

          <button onClick={handleMenuButton}
            className="text-muted-foreground hover:text-foreground rounded-md p-2.5 transition-colors hover:bg-accent"
            title="More actions">
            <MoreVertical className="h-4 w-4" />
          </button>
        </div>
      </div>

      {menuPos && (
        <EntryContextMenu
          x={menuPos.x} y={menuPos.y}
          onClose={() => setMenuPos(null)}
          onCopyCode={handleCopyCode}
          onCopySecret={handleCopySecret}
          onShowQr={() => setShowQr(true)}
          onEdit={onEdit}
          onDelete={onDelete}
        />
      )}

      <QrCodeDialog
        open={showQr}
        onClose={() => setShowQr(false)}
        uri={buildOtpauthUri(entry)}
        title={entry.issuer}
      />
    </>
  );
}
