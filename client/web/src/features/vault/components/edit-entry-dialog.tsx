import { useState, useRef } from "react";
import { Upload, Trash2, Link as LinkIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog } from "@/components/ui/dialog";
import { EntryIcon } from "./entry-icon";
import { IconLibrarySection } from "./icon-library-section";
import { downloadIconAsDataUrl } from "@/lib/icon-fetch";
import { useVaultStore } from "@/stores/useVaultStore";
import { useIconLibraryStore } from "@/stores/useIconLibraryStore";
import { useToast } from "@/hooks/use-toast";
import { MAX_LIBRARY_ICONS } from "@/types/icon-library";
import type { VaultEntry } from "@/types/vault-types";

interface EditEntryDialogProps {
  open: boolean;
  entry: VaultEntry;
  onClose: () => void;
  onSave: (updates: { issuer: string; accountName: string; icon?: string }) => void;
}

const COMMON_EMOJIS = [
  "\u{1F512}", "\u{1F511}", "\u{1F4E7}", "\u{1F4BB}", "\u{2601}️",
  "\u{1F3E6}", "\u{1F6D2}", "\u{1F3AE}", "\u{1F4F1}", "\u{1F310}",
  "\u{1F4B3}", "\u{1F393}", "\u{2699}️", "\u{1F6E1}️", "\u{1F916}",
  "\u{1F4AC}", "\u{1F3A5}", "\u{1F3B5}", "\u{1F4DA}", "\u{2708}️",
];

const MAX_ICON_SIZE = 64;

export function EditEntryDialog({ open, entry, onClose, onSave }: EditEntryDialogProps) {
  const [issuer, setIssuer] = useState(entry.issuer);
  const [accountName, setAccountName] = useState(entry.accountName);
  const [icon, setIcon] = useState<string | undefined>(entry.icon);
  const [urlInput, setUrlInput] = useState("");
  const [fetchingUrl, setFetchingUrl] = useState(false);
  const [urlError, setUrlError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const vaultKey = useVaultStore((s) => s.vaultKey);
  const libraryLoaded = useIconLibraryStore((s) => s.loaded);
  const libraryCount = useIconLibraryStore((s) => s.icons.length);
  const loadLibrary = useIconLibraryStore((s) => s.load);
  const addIcon = useIconLibraryStore((s) => s.addIcon);
  const { toast } = useToast();

  /**
   * Add a data-URL PNG to the library AND set it as the entry's icon.
   * Upload and URL-fetch both funnel through here so every user-provided
   * icon becomes reusable. Emoji picks intentionally don't — they aren't
   * library material.
   */
  const adoptIcon = async (dataUrl: string, label: string) => {
    setIcon(dataUrl);
    if (!vaultKey) return;
    try {
      // Ensure the library is loaded so our serverVersion isn't stale.
      if (!libraryLoaded) await loadLibrary(vaultKey);
      if (useIconLibraryStore.getState().icons.length >= MAX_LIBRARY_ICONS) {
        toast(`My Icons is full (${MAX_LIBRARY_ICONS} max) — icon used on this entry only`, "info");
        return;
      }
      await addIcon(vaultKey, label, dataUrl);
    } catch (err) {
      toast(err instanceof Error ? err.message : "Couldn't save to library", "error");
    }
  };

  const handleFetchUrl = async () => {
    const url = urlInput.trim();
    if (!url) return;
    setFetchingUrl(true);
    setUrlError(null);
    const result = await downloadIconAsDataUrl(url);
    setFetchingUrl(false);
    if (result) {
      const host = (() => {
        try { return new URL(url).hostname; } catch { return "Icon"; }
      })();
      await adoptIcon(result, host);
      setUrlInput("");
    } else {
      setUrlError("Could not fetch image (CORS or invalid URL)");
    }
  };

  const handleImageUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;

    try {
      const dataUrl = await resizeToPng(file, MAX_ICON_SIZE);
      const label = file.name.replace(/\.[^.]+$/, "") || "Icon";
      await adoptIcon(dataUrl, label);
    } catch (err) {
      toast(err instanceof Error ? err.message : "Couldn't read image", "error");
    }
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSave({
      issuer: issuer.trim() || "Unknown",
      accountName: accountName.trim() || "Account",
      icon,
    });
    onClose();
  };

  const isDataUrl = icon?.startsWith("data:");
  const isEmoji = icon && !isDataUrl;
  const libraryFull = libraryLoaded && libraryCount >= MAX_LIBRARY_ICONS;

  return (
    <Dialog open={open} onClose={onClose} title="Edit Account">
        <form onSubmit={handleSubmit} className="space-y-4">
          <Input id="edit-issuer" type="text" label="Service Name" value={issuer}
            onChange={(e) => setIssuer(e.target.value)} autoFocus />
          <Input id="edit-account" type="text" label="Account" value={accountName}
            onChange={(e) => setAccountName(e.target.value)} />

          <div>
            <label className="text-sm font-medium">Icon</label>
            <div className="mt-2 flex items-center gap-3">
              {/* Preview */}
              <div className="border-input flex h-12 w-12 items-center justify-center rounded-lg border text-2xl">
                {isDataUrl ? (
                  <img src={icon} alt="" className="h-10 w-10 rounded" />
                ) : isEmoji ? (
                  icon
                ) : (
                  <EntryIcon issuer={issuer} size="lg" />
                )}
              </div>

              {/* Upload (also saves to My Icons) */}
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                onChange={(e) => void handleImageUpload(e)}
                className="hidden"
              />
              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                className="border-input hover:bg-accent inline-flex items-center gap-1.5 rounded-md border px-3 py-1.5 text-sm transition-colors"
                title={libraryFull ? "My Icons is full — uploading will apply to this entry only" : "Upload an image (also saved to My Icons)"}
              >
                <Upload className="h-3.5 w-3.5" />
                Upload
              </button>

              {/* Clear */}
              {icon && (
                <button
                  type="button"
                  onClick={() => setIcon(undefined)}
                  className="text-muted-foreground hover:text-destructive inline-flex items-center gap-1.5 rounded-md px-2 py-1.5 text-sm"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              )}
            </div>

            {/* URL input (also saves to My Icons) */}
            <div className="mt-2 flex items-center gap-2">
              <LinkIcon className="text-muted-foreground h-3.5 w-3.5 shrink-0" />
              <input
                type="url"
                value={urlInput}
                onChange={(e) => { setUrlInput(e.target.value); setUrlError(null); }}
                placeholder="https://example.com/favicon.ico"
                className="bg-background border-input flex-1 rounded-md border px-2 py-1 text-sm outline-none"
                disabled={fetchingUrl}
              />
              <button
                type="button"
                onClick={() => void handleFetchUrl()}
                disabled={!urlInput.trim() || fetchingUrl}
                className="border-input hover:bg-accent inline-flex items-center rounded-md border px-3 py-1 text-sm transition-colors disabled:opacity-50"
              >
                {fetchingUrl ? "Fetching..." : "Fetch"}
              </button>
            </div>
            {urlError && <p className="text-destructive mt-1 text-xs">{urlError}</p>}

            {/* My Icons library (picker / rename / delete) */}
            <IconLibrarySection currentIcon={icon} onPickIcon={setIcon} />

            {/* Emoji grid */}
            <div className="mt-2 flex flex-wrap gap-1">
              {COMMON_EMOJIS.map((emoji) => (
                <button
                  key={emoji}
                  type="button"
                  onClick={() => setIcon(emoji)}
                  className={`h-10 w-10 rounded text-lg transition-colors hover:bg-accent ${
                    icon === emoji ? "bg-accent ring-primary ring-2" : ""
                  }`}
                >
                  {emoji}
                </button>
              ))}
            </div>
          </div>

          <div className="flex justify-end gap-2 pt-2">
            <Button type="button" variant="secondary" size="sm" onClick={onClose}>Cancel</Button>
            <Button type="submit" size="sm">Save</Button>
          </div>
        </form>
    </Dialog>
  );
}

function resizeToPng(file: File, target: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      try {
        const canvas = document.createElement("canvas");
        canvas.width = target;
        canvas.height = target;
        const ctx = canvas.getContext("2d");
        if (!ctx) { reject(new Error("Canvas 2D not supported")); return; }
        const scale = Math.max(target / img.width, target / img.height);
        const w = img.width * scale;
        const h = img.height * scale;
        ctx.drawImage(img, (target - w) / 2, (target - h) / 2, w, h);
        resolve(canvas.toDataURL("image/png"));
      } catch (e) {
        reject(e instanceof Error ? e : new Error(String(e)));
      } finally {
        URL.revokeObjectURL(url);
      }
    };
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error("Could not read image")); };
    img.src = url;
  });
}
