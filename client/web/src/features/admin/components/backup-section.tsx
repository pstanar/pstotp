import { useState } from "react";
import { Download, Upload } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog } from "@/components/ui/dialog";
import { useToast } from "@/hooks/use-toast";
import { apiClient } from "@/lib/api-client";

export function BackupSection() {
  const { toast } = useToast();

  const [showExportDialog, setShowExportDialog] = useState(false);
  const [exportPassword, setExportPassword] = useState("");
  const [exporting, setExporting] = useState(false);

  const [showRestoreDialog, setShowRestoreDialog] = useState(false);
  const [restorePassword, setRestorePassword] = useState("");
  const [restoreFile, setRestoreFile] = useState<File | null>(null);
  const [restoring, setRestoring] = useState(false);

  const handleExport = async () => {
    if (!exportPassword) return;
    setExporting(true);
    try {
      const response = await apiClient.postRaw("/admin/backup", { password: exportPassword });
      if (!response.ok) {
        const err = await response.json().catch(() => null);
        toast(err?.error || "Backup failed", "error");
        return;
      }
      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `pstotp-backup-${new Date().toISOString().split("T")[0]}.json`;
      a.click();
      URL.revokeObjectURL(url);
      toast("Backup downloaded");
      setShowExportDialog(false);
      setExportPassword("");
    } catch {
      toast("Backup failed", "error");
    } finally {
      setExporting(false);
    }
  };

  const handleRestore = async () => {
    if (!restoreFile || !restorePassword) return;
    setRestoring(true);
    try {
      const formData = new FormData();
      formData.append("file", restoreFile);
      formData.append("password", restorePassword);
      const result = await apiClient.postForm<{ restoredUsers: number; restoredEntries: number }>(
        "/admin/restore", formData);
      toast(`Restored ${result.restoredUsers} users, ${result.restoredEntries} entries`);
      setShowRestoreDialog(false);
      setRestorePassword("");
      setRestoreFile(null);
    } catch {
      toast("Restore failed", "error");
    } finally {
      setRestoring(false);
    }
  };

  return (
    <div className="border-border mt-4 rounded-lg border p-4">
      <h3 className="text-sm font-semibold mb-3">Database Backup</h3>
      <p className="text-muted-foreground text-xs mb-3">
        Export all users and data as an encrypted backup file. Use for disaster recovery or migrating between database providers.
      </p>
      <div className="flex gap-2">
        <Button size="sm" variant="secondary" onClick={() => setShowExportDialog(true)}>
          <Download className="mr-1.5 h-3.5 w-3.5" /> Download Backup
        </Button>
        <Button size="sm" variant="secondary" onClick={() => setShowRestoreDialog(true)}>
          <Upload className="mr-1.5 h-3.5 w-3.5" /> Restore Backup
        </Button>
      </div>

      <Dialog open={showExportDialog} onClose={() => setShowExportDialog(false)} title="Download Backup">
        <form onSubmit={(e) => { e.preventDefault(); void handleExport(); }} className="space-y-4">
          <p className="text-muted-foreground text-sm">
            The backup will be encrypted with this password. You'll need it to restore.
          </p>
          <input type="text" value="" autoComplete="username" readOnly hidden aria-hidden="true" tabIndex={-1} />
          <Input id="backup-password" type="password" required label="Backup Password"
            value={exportPassword} onChange={(e) => setExportPassword(e.target.value)}
            autoComplete="new-password" autoFocus />
          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" size="sm" onClick={() => setShowExportDialog(false)}>Cancel</Button>
            <Button type="submit" size="sm" disabled={exporting || !exportPassword}>
              {exporting ? "Encrypting..." : "Download"}
            </Button>
          </div>
        </form>
      </Dialog>

      <Dialog open={showRestoreDialog} onClose={() => setShowRestoreDialog(false)} title="Restore Backup">
        <form onSubmit={(e) => { e.preventDefault(); void handleRestore(); }} className="space-y-4">
          <div className="rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-700 dark:text-amber-400">
            This will replace ALL existing data. This cannot be undone.
          </div>
          <div>
            <label className="text-sm font-medium">Backup File</label>
            <input type="file" accept=".json" className="mt-1 block w-full text-sm"
              onChange={(e) => setRestoreFile(e.target.files?.[0] ?? null)} />
          </div>
          <input type="text" value="" autoComplete="username" readOnly hidden aria-hidden="true" tabIndex={-1} />
          <Input id="restore-password" type="password" required label="Backup Password"
            value={restorePassword} onChange={(e) => setRestorePassword(e.target.value)}
            autoComplete="current-password" />
          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" size="sm" onClick={() => setShowRestoreDialog(false)}>Cancel</Button>
            <Button type="submit" size="sm" variant="destructive" disabled={restoring || !restoreFile || !restorePassword}>
              {restoring ? "Restoring..." : "Restore"}
            </Button>
          </div>
        </form>
      </Dialog>
    </div>
  );
}
