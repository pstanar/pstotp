import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { X } from "lucide-react";
import QRCode from "qrcode";

interface QrCodeDialogProps {
  open: boolean;
  onClose: () => void;
  uri: string;
  title: string;
}

const AUTO_DISMISS_SECONDS = 30;

export function QrCodeDialog({ open, onClose, uri, title }: QrCodeDialogProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const onCloseRef = useRef(onClose);
  const [countdown, setCountdown] = useState(AUTO_DISMISS_SECONDS);

  useEffect(() => {
    onCloseRef.current = onClose;
  }, [onClose]);

  useEffect(() => {
    if (!open) return;
    const handleEsc = (e: KeyboardEvent) => {
      if (e.key === "Escape") onCloseRef.current();
    };
    document.addEventListener("keydown", handleEsc);
    return () => document.removeEventListener("keydown", handleEsc);
  }, [open]);

  useEffect(() => {
    if (!open || !canvasRef.current) return;
    const size = Math.min(256, window.innerWidth - 80);
    void QRCode.toCanvas(canvasRef.current, uri, { width: size, margin: 2 });
  }, [open, uri]);

  useEffect(() => {
    if (!open) return;

    const start = Date.now();
    const tick = setInterval(() => {
      const elapsed = Math.floor((Date.now() - start) / 1000);
      const remaining = AUTO_DISMISS_SECONDS - elapsed;
      if (remaining <= 0) {
        onCloseRef.current();
      } else {
        setCountdown(remaining);
      }
    }, 500);

    return () => clearInterval(tick);
  }, [open]);

  if (!open) return null;

  // Portal to body so the fixed overlay isn't trapped by ancestor stacking
  // contexts created by dnd-kit's transform/transition styles on SortableCard.
  return createPortal((
    <div className="fixed inset-0 z-[60] flex items-center justify-center overflow-y-auto bg-black/50 p-4 backdrop-blur-[2px]" onClick={onClose}>
      <div
        className="bg-background mx-4 w-full max-w-xs rounded-lg border p-4 shadow-xl sm:p-6"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-sm font-semibold truncate">{title}</h2>
          <button onClick={onClose} className="text-muted-foreground hover:text-foreground -mr-1 p-2">
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="flex justify-center">
          <canvas ref={canvasRef} />
        </div>

        <p className="text-muted-foreground mt-3 text-center text-xs">
          Auto-closes in {countdown}s
        </p>

        <button
          onClick={onClose}
          className="border-input hover:bg-accent mt-4 w-full rounded-md border px-4 py-2 text-sm font-medium transition-colors"
        >
          Close
        </button>
      </div>
    </div>
  ), document.body);
}
