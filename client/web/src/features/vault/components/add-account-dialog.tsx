import { useState, useRef, useEffect, useCallback } from "react";
import { Camera, ImageIcon, ClipboardPaste, ChevronDown } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog } from "@/components/ui/dialog";
import jsQR from "jsqr";
import { parseOtpauthUri } from "@/features/vault/utils/totp";
import { useQrScanner } from "@/features/vault/hooks/use-qr-scanner";

interface AddAccountDialogProps {
  open: boolean;
  onClose: () => void;
  onAdd: (entry: {
    issuer: string;
    accountName: string;
    secret: string;
    algorithm: string;
    digits: number;
    period: number;
  }) => void;
}

type Mode = "scan" | "image" | "uri" | "manual";

export function AddAccountDialog({ open, onClose, onAdd }: AddAccountDialogProps) {
  const [mode, setMode] = useState<Mode>("scan");
  const [uri, setUri] = useState("");
  const [issuer, setIssuer] = useState("");
  const [accountName, setAccountName] = useState("");
  const [secret, setSecret] = useState("");
  const [algorithm, setAlgorithm] = useState("SHA1");
  const [digits, setDigits] = useState("6");
  const [period, setPeriod] = useState("30");
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const reset = useCallback(() => {
    setUri(""); setIssuer(""); setAccountName(""); setSecret("");
    setAlgorithm("SHA1"); setDigits("6"); setPeriod("30"); setShowAdvanced(false);
    setError(null); setMode("scan");
  }, []);

  const handleAdd = useCallback((data: string) => {
    onAdd(parseOtpauthUri(data));
  }, [onAdd]);

  const handleQrResult = useCallback((data: string) => {
    try { handleAdd(data); reset(); onClose(); }
    catch { setError("QR code does not contain a valid otpauth:// URI"); }
  }, [handleAdd, reset, onClose]);

  const handleQrError = useCallback((msg: string) => setError(msg), []);

  const { videoRef, canvasRef, scanning, stop: stopCamera } = useQrScanner({
    active: open && mode === "scan",
    onResult: handleQrResult,
    onError: handleQrError,
  });

  const decodeQrFromFile = useCallback((file: Blob) => {
    setError(null);
    const img = new Image();
    img.onload = () => {
      const canvas = document.createElement("canvas");
      canvas.width = img.width;
      canvas.height = img.height;
      const ctx = canvas.getContext("2d", { willReadFrequently: true });
      if (!ctx) return;
      ctx.drawImage(img, 0, 0);
      const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
      const code = jsQR(imageData.data, imageData.width, imageData.height);
      if (code?.data) {
        try { handleAdd(code.data); reset(); onClose(); }
        catch { setError("QR code does not contain a valid otpauth:// URI"); }
      } else {
        setError("No QR code found in image");
      }
      URL.revokeObjectURL(img.src);
    };
    img.onerror = () => setError("Failed to load image");
    img.src = URL.createObjectURL(file);
  }, [handleAdd, reset, onClose]);

  useEffect(() => {
    if (!open || mode !== "image") return;
    const onPaste = (e: ClipboardEvent) => {
      const items = e.clipboardData?.items;
      if (!items) return;
      for (const item of items) {
        if (item.type.startsWith("image/")) {
          e.preventDefault();
          const file = item.getAsFile();
          if (file) decodeQrFromFile(file);
          return;
        }
      }
    };
    document.addEventListener("paste", onPaste);
    return () => document.removeEventListener("paste", onPaste);
  }, [open, mode, decodeQrFromFile]);

  const handleClose = () => { stopCamera(); reset(); onClose(); };
  const switchMode = (m: Mode) => { stopCamera(); setError(null); setMode(m); };

  return (
    <Dialog open={open} onClose={handleClose} title="Add Account">
        <div className="mb-4 flex gap-2 flex-wrap">
          <button onClick={() => switchMode("scan")}
            className={`rounded-md px-3 py-1.5 text-sm font-medium inline-flex items-center gap-1.5 ${
              mode === "scan" ? "bg-primary text-primary-foreground" : "bg-muted"}`}>
            <Camera className="h-3.5 w-3.5" />Scan QR
          </button>
          <button onClick={() => switchMode("image")}
            className={`rounded-md px-3 py-1.5 text-sm font-medium inline-flex items-center gap-1.5 ${
              mode === "image" ? "bg-primary text-primary-foreground" : "bg-muted"}`}>
            <ImageIcon className="h-3.5 w-3.5" />From Image
          </button>
          <button onClick={() => switchMode("uri")}
            className={`rounded-md px-3 py-1.5 text-sm font-medium ${
              mode === "uri" ? "bg-primary text-primary-foreground" : "bg-muted"}`}>
            Paste URI
          </button>
          <button onClick={() => switchMode("manual")}
            className={`rounded-md px-3 py-1.5 text-sm font-medium ${
              mode === "manual" ? "bg-primary text-primary-foreground" : "bg-muted"}`}>
            Manual
          </button>
        </div>

        {mode === "scan" && (
          <div className="space-y-4">
            <div className="relative aspect-square w-full overflow-hidden rounded-lg bg-black">
              <video ref={videoRef} className="h-full w-full object-cover" playsInline muted />
              <canvas ref={canvasRef} className="hidden" />
              {scanning && (
                <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
                  <div className="h-36 w-36 rounded-lg border-2 border-white/50 sm:h-48 sm:w-48" />
                </div>
              )}
            </div>
            {error && <p className="text-destructive text-sm">{error}</p>}
            <p className="text-muted-foreground text-center text-sm">Point your camera at a QR code</p>
          </div>
        )}

        {mode === "image" && (
          <div className="space-y-4">
            <input ref={fileInputRef} type="file" accept="image/*"
              onChange={(e) => { const f = e.target.files?.[0]; if (f) decodeQrFromFile(f); e.target.value = ""; }}
              className="hidden" />
            <div className="flex gap-3">
              <button onClick={() => fileInputRef.current?.click()}
                className="border-input hover:bg-accent flex flex-1 flex-col items-center gap-2 rounded-lg border-2 border-dashed p-6 text-sm">
                <ImageIcon className="text-muted-foreground h-8 w-8" />
                <span className="text-muted-foreground">Select image</span>
              </button>
              <button onClick={async () => {
                try {
                  const items = await navigator.clipboard.read();
                  for (const item of items) {
                    const t = item.types.find(t => t.startsWith("image/"));
                    if (t) { decodeQrFromFile(await item.getType(t)); return; }
                  }
                  setError("No image found in clipboard");
                } catch { setError("Clipboard access denied. Try Ctrl+V instead."); }
              }}
                className="border-input hover:bg-accent flex flex-1 flex-col items-center gap-2 rounded-lg border-2 border-dashed p-6 text-sm">
                <ClipboardPaste className="text-muted-foreground h-8 w-8" />
                <span className="text-muted-foreground">Paste from clipboard</span>
              </button>
            </div>
            {error && <p className="text-destructive text-sm">{error}</p>}
          </div>
        )}

        {mode === "uri" && (
          <form onSubmit={(e) => {
            e.preventDefault(); setError(null);
            try { handleAdd(uri.trim()); reset(); onClose(); }
            catch (err) { setError(err instanceof Error ? err.message : "Invalid URI"); }
          }} className="space-y-4">
            <Input id="otpauth-uri" type="text" required label="otpauth:// URI" value={uri}
              onChange={(e) => setUri(e.target.value)}
              placeholder="otpauth://totp/Issuer:account?secret=..." autoFocus />
            {error && <p className="text-destructive text-sm">{error}</p>}
            <Button type="submit" className="w-full">Add</Button>
          </form>
        )}

        {mode === "manual" && (
          <form onSubmit={(e) => {
            e.preventDefault(); setError(null);
            const s = secret.trim().replace(/\s/g, "");
            if (!s) { setError("Secret key is required"); return; }
            const d = parseInt(digits, 10);
            if (!d || d < 4 || d > 10) { setError("Digits must be between 4 and 10"); return; }
            const p = parseInt(period, 10);
            if (!p || p <= 0) { setError("Period must be a positive number"); return; }
            onAdd({
              issuer: issuer.trim() || "Unknown",
              accountName: accountName.trim() || issuer.trim() || "Account",
              secret: s.toUpperCase(), algorithm, digits: d, period: p,
            });
            reset(); onClose();
          }} className="space-y-4">
            <Input id="issuer" type="text" label="Service Name" value={issuer}
              onChange={(e) => setIssuer(e.target.value)} placeholder="Google, GitHub, etc." autoFocus />
            <Input id="account-name" type="text" label="Account" value={accountName}
              onChange={(e) => setAccountName(e.target.value)} placeholder="alice@example.com" />
            <Input id="secret-key" type="text" required label="Secret Key" value={secret}
              onChange={(e) => setSecret(e.target.value)} className="font-mono" placeholder="JBSWY3DPEHPK3PXP" />

            <button type="button" onClick={() => setShowAdvanced(!showAdvanced)}
              className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground transition-colors">
              <ChevronDown className={`h-4 w-4 transition-transform ${showAdvanced ? "rotate-180" : ""}`} />
              Advanced
            </button>

            {showAdvanced && (
              <div className="space-y-3 rounded-md border border-border bg-muted/30 p-3">
                <div>
                  <label htmlFor="algorithm" className="mb-1.5 block text-sm font-medium">Algorithm</label>
                  <select id="algorithm" value={algorithm} onChange={(e) => setAlgorithm(e.target.value)}
                    className="border-input bg-background w-full rounded-md border px-3 py-2 text-sm shadow-sm focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20">
                    <option value="SHA1">SHA-1 (default)</option>
                    <option value="SHA256">SHA-256</option>
                    <option value="SHA512">SHA-512</option>
                  </select>
                </div>
                <Input id="digits" type="number" label="Digits" value={digits}
                  onChange={(e) => setDigits(e.target.value)} min={4} max={10} placeholder="6" />
                <Input id="period" type="number" label="Period (seconds)" value={period}
                  onChange={(e) => setPeriod(e.target.value)} min={1} />
              </div>
            )}

            {error && <p className="text-destructive text-sm">{error}</p>}
            <Button type="submit" className="w-full">Add</Button>
          </form>
        )}
    </Dialog>
  );
}
