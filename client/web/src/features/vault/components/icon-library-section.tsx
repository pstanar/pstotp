import { useEffect, useRef, useState } from "react";
import { Upload, Trash2, Pencil, Check, X } from "lucide-react";
import { useVaultStore } from "@/stores/useVaultStore";
import { useIconLibraryStore } from "@/stores/useIconLibraryStore";
import { useToast } from "@/hooks/use-toast";
import { MAX_LIBRARY_ICONS } from "@/types/icon-library";

const TARGET_SIZE = 64;

interface Props {
  /** Current icon on the entry being edited (data-URL, emoji, or undefined). */
  currentIcon: string | undefined;
  /** Picked-from-library or uploaded icon flows through here. */
  onPickIcon: (dataUrl: string) => void;
}

/**
 * "My Icons" — the user-scoped reusable icon library. Rendered inside the
 * Add / Edit Account dialogs. Contributing a custom icon (upload) saves
 * it to the library so it's reusable across entries. Picking a library
 * icon copies its bytes into the entry being edited (see
 * docs: copy-not-reference model). Deleting from the library does not
 * affect any entry that previously picked the icon.
 */
export function IconLibrarySection({ currentIcon, onPickIcon }: Props) {
  const vaultKey = useVaultStore((s) => s.vaultKey);
  const { icons, loaded, loadError, load, addIcon, removeIcon, renameIcon } =
    useIconLibraryStore();
  const { toast } = useToast();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameDraft, setRenameDraft] = useState("");

  useEffect(() => {
    if (vaultKey && !loaded) void load(vaultKey);
  }, [vaultKey, loaded, load]);

  const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file || !vaultKey) return;
    if (icons.length >= MAX_LIBRARY_ICONS) {
      toast(`Library full (${MAX_LIBRARY_ICONS} max). Delete some icons first.`, "error");
      return;
    }
    setBusy(true);
    try {
      const dataUrl = await resizeToPng(file, TARGET_SIZE);
      const label = file.name.replace(/\.[^.]+$/, "") || "Icon";
      await addIcon(vaultKey, label, dataUrl);
      // Also pick the newly-added icon onto the entry being edited.
      onPickIcon(dataUrl);
    } catch (err) {
      toast(err instanceof Error ? err.message : "Failed to add icon", "error");
    } finally {
      setBusy(false);
    }
  };

  const handleRemove = async (id: string) => {
    if (!vaultKey) return;
    setBusy(true);
    try {
      await removeIcon(vaultKey, id);
    } catch (err) {
      toast(err instanceof Error ? err.message : "Failed to remove icon", "error");
    } finally {
      setBusy(false);
    }
  };

  const startRename = (id: string, currentLabel: string) => {
    setRenamingId(id);
    setRenameDraft(currentLabel);
  };

  const commitRename = async () => {
    if (!renamingId || !vaultKey) return;
    setBusy(true);
    try {
      await renameIcon(vaultKey, renamingId, renameDraft);
    } catch (err) {
      toast(err instanceof Error ? err.message : "Failed to rename", "error");
    } finally {
      setBusy(false);
      setRenamingId(null);
      setRenameDraft("");
    }
  };

  return (
    <div className="border-border mt-2 rounded-md border p-2">
      <div className="mb-2 flex items-center justify-between">
        <span className="text-muted-foreground text-xs font-medium uppercase tracking-wide">
          My icons {icons.length > 0 && `(${icons.length}/${MAX_LIBRARY_ICONS})`}
        </span>
        <input
          ref={fileInputRef}
          type="file"
          accept="image/*"
          onChange={(e) => void handleUpload(e)}
          className="hidden"
        />
        <button
          type="button"
          disabled={busy || !vaultKey || icons.length >= MAX_LIBRARY_ICONS}
          onClick={() => fileInputRef.current?.click()}
          className="border-input hover:bg-accent inline-flex items-center gap-1 rounded-md border px-2 py-1 text-xs transition-colors disabled:opacity-50"
          title={icons.length >= MAX_LIBRARY_ICONS ? "Library is full" : "Upload a custom icon"}
        >
          <Upload className="h-3 w-3" />
          Add
        </button>
      </div>

      {loadError && (
        <p className="text-destructive text-xs">
          Couldn't load library: {loadError}
        </p>
      )}

      {!loadError && icons.length === 0 && (
        <p className="text-muted-foreground text-xs">
          No custom icons yet. Upload one with the <strong>Add</strong> button; it'll
          be available for any account.
        </p>
      )}

      {icons.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {icons.map((icon) => {
            const isSelected = currentIcon === icon.data;
            const isRenaming = renamingId === icon.id;
            return (
              <div key={icon.id} className="group relative">
                <button
                  type="button"
                  onClick={() => onPickIcon(icon.data)}
                  title={icon.label}
                  className={`hover:bg-accent flex h-10 w-10 items-center justify-center rounded transition-colors ${
                    isSelected ? "ring-primary ring-2" : ""
                  }`}
                >
                  <img src={icon.data} alt={icon.label} className="h-8 w-8 rounded" />
                </button>
                <div className="absolute -right-1 -top-1 hidden gap-0.5 group-hover:flex">
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => startRename(icon.id, icon.label)}
                    className="bg-popover border-border text-muted-foreground hover:text-foreground rounded-full border p-0.5 shadow-sm"
                    title="Rename"
                  >
                    <Pencil className="h-2.5 w-2.5" />
                  </button>
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => void handleRemove(icon.id)}
                    className="bg-popover border-border text-muted-foreground hover:text-destructive rounded-full border p-0.5 shadow-sm"
                    title="Delete (existing entries keep their copy)"
                  >
                    <Trash2 className="h-2.5 w-2.5" />
                  </button>
                </div>
                {isRenaming && (
                  <div className="bg-popover border-border absolute left-0 top-full z-10 mt-1 flex items-center gap-1 rounded-md border p-1 shadow-md">
                    <input
                      type="text"
                      value={renameDraft}
                      onChange={(e) => setRenameDraft(e.target.value)}
                      autoFocus
                      className="bg-background border-input w-32 rounded border px-1.5 py-0.5 text-xs outline-none"
                      onKeyDown={(e) => {
                        if (e.key === "Enter") void commitRename();
                        if (e.key === "Escape") {
                          setRenamingId(null);
                          setRenameDraft("");
                        }
                      }}
                    />
                    <button
                      type="button"
                      onClick={() => void commitRename()}
                      className="hover:bg-accent rounded p-1"
                      title="Save"
                    >
                      <Check className="h-3 w-3" />
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setRenamingId(null);
                        setRenameDraft("");
                      }}
                      className="hover:bg-accent rounded p-1"
                      title="Cancel"
                    >
                      <X className="h-3 w-3" />
                    </button>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

/**
 * Read an image file, scale it to cover target×target, centre-crop, and
 * return a data-URL PNG. Keeps the behaviour consistent with the inline
 * upload path that already existed in the edit dialog.
 */
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
        if (!ctx) {
          reject(new Error("Canvas 2D not supported"));
          return;
        }
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
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("Could not read image"));
    };
    img.src = url;
  });
}
