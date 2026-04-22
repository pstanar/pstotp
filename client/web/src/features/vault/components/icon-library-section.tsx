import { useEffect, useState } from "react";
import { Trash2, Pencil, Check, X } from "lucide-react";
import { useVaultStore } from "@/stores/useVaultStore";
import { useIconLibraryStore } from "@/stores/useIconLibraryStore";
import { useToast } from "@/hooks/use-toast";
import { MAX_LIBRARY_ICONS } from "@/types/icon-library";

interface Props {
  /** Current icon on the entry being edited. */
  currentIcon: string | undefined;
  /** Called when the user picks an icon from the library. */
  onPickIcon: (dataUrl: string) => void;
}

/**
 * "My Icons" — picker for the user-scoped reusable icon library.
 * Uploading and URL-fetching happen in the parent dialog and auto-
 * populate this library, so this component is picker-only: tap to
 * pick, hover for rename / delete actions. Library is capped at
 * MAX_LIBRARY_ICONS; list scrolls after ~3 rows so the dialog
 * doesn't grow unbounded.
 */
export function IconLibrarySection({ currentIcon, onPickIcon }: Props) {
  const vaultKey = useVaultStore((s) => s.vaultKey);
  const { icons, loaded, loadError, load, removeIcon, renameIcon } =
    useIconLibraryStore();
  const { toast } = useToast();
  const [busy, setBusy] = useState(false);
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameDraft, setRenameDraft] = useState("");

  useEffect(() => {
    if (vaultKey && !loaded) void load(vaultKey);
  }, [vaultKey, loaded, load]);

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
          My icons{icons.length > 0 && ` (${icons.length}/${MAX_LIBRARY_ICONS})`}
        </span>
      </div>

      {loadError && (
        <p className="text-destructive text-xs">
          Couldn't load library: {loadError}
        </p>
      )}

      {!loadError && icons.length === 0 && (
        <p className="text-muted-foreground text-xs">
          No custom icons yet. Upload an image or fetch one from a URL —
          it'll be saved here for reuse.
        </p>
      )}

      {icons.length > 0 && (
        <div className="max-h-36 overflow-y-auto pr-1">
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
                    className={`block border-2 transition-colors focus:outline-none focus-visible:border-primary ${
                      isSelected ? "border-primary" : "border-transparent hover:border-muted-foreground/40"
                    }`}
                  >
                    <img src={icon.data} alt={icon.label} className="block h-8 w-8" />
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
        </div>
      )}
    </div>
  );
}
