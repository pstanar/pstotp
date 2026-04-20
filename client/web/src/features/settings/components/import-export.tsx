import { useState, useRef } from "react";
import { Download, Upload, AlertTriangle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog } from "@/components/ui/dialog";
import { useToast } from "@/hooks/use-toast";
import { useVaultStore } from "@/stores/useVaultStore";
import {
  derivePasswordAuthKey,
  derivePasswordEnvelopeKey,
  generateSalt,
  aesGcmEncrypt,
  aesGcmDecrypt,
  fromBase64,
  toBase64,
} from "@/lib/crypto";
import { parseOtpauthUri } from "@/features/vault/utils/totp";
import { buildOtpauthUri } from "@/features/vault/utils/otpauth-uri";
import {
  tryParseGoogleAuthMigration,
  tryParseAegis,
  tryParse2Fas,
} from "@/features/vault/utils/external-imports";
import { encryptEntry } from "@/features/vault/utils/vault-crypto";
import { upsertEntry } from "@/features/vault/api/vault-api";
import { apiClient } from "@/lib/api-client";
import { downloadIconAsDataUrl, isIconUrl } from "@/lib/icon-fetch";
import type { KdfConfig } from "@/types/api-types";
import type { VaultEntry, VaultEntryPlaintext } from "@/types/vault-types";
import { cn } from "@/lib/css-utils";

type ImportAction = "overwrite" | "add" | "skip";

interface ImportCandidate {
  imported: VaultEntryPlaintext;
  existingMatch: VaultEntry | null;
  action: ImportAction;
}

function findMatch(entry: VaultEntryPlaintext, existing: VaultEntry[]): VaultEntry | null {
  return existing.find(e =>
    e.issuer.toLowerCase() === entry.issuer.toLowerCase() &&
    e.accountName.toLowerCase() === entry.accountName.toLowerCase()
  ) ?? null;
}

function buildCandidates(imported: VaultEntryPlaintext[], existing: VaultEntry[]): ImportCandidate[] {
  return imported.map(entry => {
    const match = findMatch(entry, existing);
    return { imported: entry, existingMatch: match, action: match ? "overwrite" : "add" };
  });
}

async function resolveIconUrls(
  entries: VaultEntryPlaintext[],
  onProgress?: (done: number, total: number) => void,
): Promise<VaultEntryPlaintext[]> {
  const withUrls = entries.filter(e => isIconUrl(e.icon));
  if (withUrls.length === 0) return entries;

  let done = 0;
  onProgress?.(0, withUrls.length);

  const iconByUrl = new Map<string, string | null>();
  for (const entry of withUrls) {
    const url = entry.icon!;
    if (!iconByUrl.has(url)) {
      iconByUrl.set(url, await downloadIconAsDataUrl(url));
    }
    done++;
    onProgress?.(done, withUrls.length);
  }

  return entries.map(e => {
    if (!isIconUrl(e.icon)) return e;
    const resolved = iconByUrl.get(e.icon!);
    return { ...e, icon: resolved ?? undefined };
  });
}

function makeUniqueName(name: string, issuer: string, existing: VaultEntry[]): string {
  const taken = new Set(
    existing
      .filter(e => e.issuer.toLowerCase() === issuer.toLowerCase())
      .map(e => e.accountName.toLowerCase())
  );
  if (!taken.has(name.toLowerCase())) return name;
  for (let i = 2; ; i++) {
    const candidate = `${name} (${i})`;
    if (!taken.has(candidate.toLowerCase())) return candidate;
  }
}

export function ImportExport() {
  const { toast } = useToast();
  const entries = useVaultStore((s) => s.entries);
  const vaultKey = useVaultStore((s) => s.vaultKey);
  const addEntry = useVaultStore((s) => s.addEntry);
  const updateEntry = useVaultStore((s) => s.updateEntry);

  // Export state
  const [showExportDialog, setShowExportDialog] = useState(false);
  const [exportPassword, setExportPassword] = useState("");
  const [exportFormat, setExportFormat] = useState<"encrypted" | "plain" | "otpauth">("encrypted");
  const [exporting, setExporting] = useState(false);

  // Import state
  const [showImportDialog, setShowImportDialog] = useState(false);
  const [importPassword, setImportPassword] = useState("");
  const [importFile, setImportFile] = useState<File | null>(null);
  const [importing, setImporting] = useState(false);
  const [importCandidates, setImportCandidates] = useState<ImportCandidate[] | null>(null);
  const [duplicateAction, setDuplicateAction] = useState<ImportAction>("overwrite");
  const [iconProgress, setIconProgress] = useState<{ done: number; total: number } | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleExport = async () => {
    if (exportFormat === "encrypted" && !exportPassword) return;
    setExporting(true);
    try {
      const plainEntries = entries.map(e => ({
        issuer: e.issuer,
        accountName: e.accountName,
        secret: e.secret,
        algorithm: e.algorithm,
        digits: e.digits,
        period: e.period,
        icon: e.icon,
      }));

      let fileContent: string;
      let fileName: string;

      if (exportFormat === "encrypted") {
        const salt = generateSalt();
        const kdf: KdfConfig = { algorithm: "argon2id", memoryMb: 64, iterations: 3, parallelism: 4, salt: toBase64(salt) };
        const authKey = await derivePasswordAuthKey(exportPassword, salt, kdf);
        const encKey = await derivePasswordEnvelopeKey(authKey);
        const plainJson = new TextEncoder().encode(JSON.stringify(plainEntries));
        const encrypted = await aesGcmEncrypt(encKey, plainJson);

        fileContent = JSON.stringify({
          version: 1,
          format: "pstotp-export",
          salt: toBase64(salt),
          payload: toBase64(new Uint8Array([...encrypted.ciphertext, ...encrypted.nonce])),
          ciphertext: toBase64(encrypted.ciphertext),
          nonce: toBase64(encrypted.nonce),
        });
        fileName = `pstotp-export-${new Date().toISOString().split("T")[0]}.json`;
      } else if (exportFormat === "otpauth") {
        fileContent = entries.map(e => buildOtpauthUri(e)).join("\n");
        fileName = `pstotp-export-${new Date().toISOString().split("T")[0]}.txt`;
      } else {
        fileContent = JSON.stringify({ version: 1, format: "pstotp-plain", entries: plainEntries }, null, 2);
        fileName = `pstotp-export-${new Date().toISOString().split("T")[0]}-PLAIN.json`;
      }

      const mimeType = exportFormat === "otpauth" ? "text/plain" : "application/json";
      const blob = new Blob([fileContent], { type: mimeType });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = fileName;
      a.click();
      URL.revokeObjectURL(url);
      toast("Vault exported");
      void apiClient.post("/account/vault/exported");
      setShowExportDialog(false);
      setExportPassword("");
    } catch {
      toast("Export failed", "error");
    } finally {
      setExporting(false);
    }
  };

  const handleImportFile = async (file?: File) => {
    const f = file ?? importFile;
    if (!f) return;
    try {
      const text = await f.text();

      const trimmed = text.trim();

      // otpauth-migration:// (Google Authenticator) — check first so it
      // doesn't fall into the plain otpauth:// branch.
      if (trimmed.startsWith("otpauth-migration://")) {
        const parsed = tryParseGoogleAuthMigration(trimmed);
        if (!parsed || parsed.length === 0) {
          toast("No TOTP accounts found in Google Authenticator export", "error");
          return;
        }
        const resolved = await resolveIconUrls(parsed, (done, total) => setIconProgress({ done, total }));
        setIconProgress(null);
        setImportCandidates(buildCandidates(resolved, entries));
        return;
      }

      // Plain otpauth:// URI list (one per line)
      if (trimmed.startsWith("otpauth://")) {
        const lines = trimmed.split("\n").filter(l => l.trim().startsWith("otpauth://"));
        const parsed = lines.map(line => parseOtpauthUri(line.trim()));
        const resolved = await resolveIconUrls(parsed, (done, total) => setIconProgress({ done, total }));
        setIconProgress(null);
        setImportCandidates(buildCandidates(resolved, entries));
        return;
      }

      // JSON formats
      let json: unknown;
      try {
        json = JSON.parse(text);
      } catch {
        toast("Unrecognized file format", "error");
        return;
      }

      const asRecord = json as Record<string, unknown>;
      if (asRecord.format === "pstotp-export" && asRecord.ciphertext && asRecord.nonce) {
        // Encrypted — need password
        setShowImportDialog(true);
        return;
      }
      if (asRecord.format === "pstotp-plain" && Array.isArray(asRecord.entries)) {
        const resolved = await resolveIconUrls(asRecord.entries as VaultEntryPlaintext[], (done, total) => setIconProgress({ done, total }));
        setIconProgress(null);
        setImportCandidates(buildCandidates(resolved, entries));
        return;
      }

      const aegis = tryParseAegis(json);
      if (aegis) {
        const resolved = await resolveIconUrls(aegis, (done, total) => setIconProgress({ done, total }));
        setIconProgress(null);
        setImportCandidates(buildCandidates(resolved, entries));
        return;
      }

      const twoFas = tryParse2Fas(json);
      if (twoFas) {
        const resolved = await resolveIconUrls(twoFas, (done, total) => setIconProgress({ done, total }));
        setIconProgress(null);
        setImportCandidates(buildCandidates(resolved, entries));
        return;
      }

      toast("Unrecognized file format", "error");
    } catch {
      toast("Failed to read file", "error");
    }
  };

  const handleDecryptImport = async () => {
    if (!importFile || !importPassword) return;
    setImporting(true);
    try {
      const text = await importFile.text();
      const json = JSON.parse(text);
      const salt = fromBase64(json.salt);
      const kdf: KdfConfig = { algorithm: "argon2id", memoryMb: 64, iterations: 3, parallelism: 4, salt: json.salt };
      const authKey = await derivePasswordAuthKey(importPassword, salt, kdf);
      const encKey = await derivePasswordEnvelopeKey(authKey);
      const ciphertext = fromBase64(json.ciphertext);
      const nonce = fromBase64(json.nonce);
      const plainBytes = await aesGcmDecrypt(encKey, ciphertext, nonce);
      const decrypted: VaultEntryPlaintext[] = JSON.parse(new TextDecoder().decode(plainBytes));
      const resolved = await resolveIconUrls(decrypted, (done, total) => setIconProgress({ done, total }));
      setIconProgress(null);
      setImportCandidates(buildCandidates(resolved, entries));
      setShowImportDialog(false);
    } catch {
      toast("Incorrect password or corrupted file", "error");
    } finally {
      setImporting(false);
    }
  };

  const handleDuplicateActionChange = (action: ImportAction) => {
    setDuplicateAction(action);
    setImportCandidates(prev => prev?.map(c =>
      c.existingMatch ? { ...c, action } : c
    ) ?? null);
  };

  const handleConfirmImport = async () => {
    if (!importCandidates || !vaultKey) return;
    setImporting(true);
    try {
      let imported = 0;
      const allEntries = [...entries]; // Track additions for name deduplication
      for (const candidate of importCandidates) {
        if (candidate.action === "skip") continue;

        if (candidate.action === "overwrite" && candidate.existingMatch) {
          const id = candidate.existingMatch.id;
          const version = candidate.existingMatch.version;
          const payload = await encryptEntry(vaultKey, candidate.imported, id);
          const response = await upsertEntry(id, payload, version);
          updateEntry(id, { ...candidate.imported, version: response.entryVersion });
        } else {
          const id = crypto.randomUUID();
          const plaintext = { ...candidate.imported };
          if (candidate.existingMatch) {
            plaintext.accountName = makeUniqueName(plaintext.accountName, plaintext.issuer, allEntries);
          }
          const entry: VaultEntry = { ...plaintext, id, version: 1 };
          const payload = await encryptEntry(vaultKey, plaintext, id);
          await upsertEntry(id, payload, 0);
          addEntry(entry);
          allEntries.push(entry);
        }
        imported++;
      }
      toast(`Imported ${imported} entries`);
      void apiClient.post("/account/vault/imported");
      setImportCandidates(null);
      setImportFile(null);
    } catch {
      toast("Import failed", "error");
    } finally {
      setImporting(false);
    }
  };

  return (
    <div>
      <label className="text-sm font-medium">Import & Export</label>
      <p className="text-muted-foreground mt-0.5 mb-3 text-sm">
        Export your vault entries or import from another authenticator.
      </p>

      <div className="flex gap-2">
        <Button size="sm" variant="secondary" onClick={() => setShowExportDialog(true)}>
          <Download className="mr-1.5 h-3.5 w-3.5" /> Export
        </Button>
        <Button size="sm" variant="secondary" onClick={() => fileInputRef.current?.click()}>
          <Upload className="mr-1.5 h-3.5 w-3.5" /> Import
        </Button>
        <input ref={fileInputRef} type="file" accept=".json,.txt" className="hidden"
          onChange={(e) => { const f = e.target.files?.[0]; if (f) { setImportFile(f); void handleImportFile(f); } e.target.value = ""; }} />
      </div>

      {iconProgress && (
        <p className="mt-2 text-xs text-muted-foreground">
          Downloading icons... {iconProgress.done} / {iconProgress.total}
        </p>
      )}

      {/* Import preview with conflict resolution */}
      {importCandidates && (() => {
        const duplicates = importCandidates.filter(c => c.existingMatch);
        const activeCount = importCandidates.filter(c => c.action !== "skip").length;

        return (
          <div className="mt-3 rounded-md border border-border p-3 space-y-2">
            <p className="text-sm font-medium">
              {importCandidates.length} entries found
              {duplicates.length > 0 && (
                <span className="text-amber-600 dark:text-amber-400">
                  {" "}({duplicates.length} duplicate{duplicates.length !== 1 ? "s" : ""})
                </span>
              )}
            </p>

            {duplicates.length > 0 && (
              <div className="flex items-center gap-2 text-xs">
                <span className="text-muted-foreground">Duplicates:</span>
                <div className="flex gap-1">
                  {(["overwrite", "add", "skip"] as const).map(action => (
                    <Button key={action} type="button" size="sm"
                      variant={duplicateAction === action ? "primary" : "secondary"}
                      className="h-6 px-2 text-[11px]"
                      onClick={() => handleDuplicateActionChange(action)}>
                      {action === "overwrite" ? "Overwrite" : action === "add" ? "Add copy" : "Skip"}
                    </Button>
                  ))}
                </div>
              </div>
            )}

            <div className="max-h-48 overflow-y-auto space-y-1">
              {importCandidates.map((c, i) => (
                <div key={i} className={cn(
                  "flex items-center justify-between text-xs rounded px-1.5 py-0.5",
                  c.action === "skip" ? "text-muted-foreground/50 line-through" : "text-muted-foreground",
                  c.existingMatch && "bg-amber-500/5"
                )}>
                  <span>
                    {c.imported.issuer} — {c.imported.accountName}
                    {c.existingMatch && (
                      <span className="ml-1.5 text-[10px] text-amber-600 dark:text-amber-400 font-medium uppercase">
                        duplicate
                      </span>
                    )}
                  </span>
                  {c.existingMatch && (
                    <select
                      className="ml-2 h-5 shrink-0 rounded border border-input bg-background px-1 text-[11px]"
                      value={c.action}
                      onChange={(e) => {
                        setImportCandidates(prev => prev?.map((p, j) =>
                          j === i ? { ...p, action: e.target.value as ImportAction } : p
                        ) ?? null);
                      }}>
                      <option value="overwrite">Overwrite</option>
                      <option value="add">Add copy</option>
                      <option value="skip">Skip</option>
                    </select>
                  )}
                </div>
              ))}
            </div>

            <div className="flex gap-2">
              <Button size="sm" onClick={() => void handleConfirmImport()} disabled={importing || activeCount === 0}>
                {importing ? "Importing..." : `Import ${activeCount} ${activeCount === 1 ? "entry" : "entries"}`}
              </Button>
              <Button size="sm" variant="secondary" onClick={() => setImportCandidates(null)}>
                Cancel
              </Button>
            </div>
          </div>
        );
      })()}

      {/* Export dialog */}
      <Dialog open={showExportDialog} onClose={() => setShowExportDialog(false)} title="Export Vault">
        <form onSubmit={(e) => { e.preventDefault(); void handleExport(); }} className="space-y-4">
          <div className="flex gap-2">
            <Button type="button" size="sm"
              variant={exportFormat === "encrypted" ? "primary" : "secondary"}
              onClick={() => setExportFormat("encrypted")}>
              Encrypted
            </Button>
            <Button type="button" size="sm"
              variant={exportFormat === "plain" ? "primary" : "secondary"}
              onClick={() => setExportFormat("plain")}>
              Plain JSON
            </Button>
            <Button type="button" size="sm"
              variant={exportFormat === "otpauth" ? "primary" : "secondary"}
              onClick={() => setExportFormat("otpauth")}>
              otpauth:// URIs
            </Button>
          </div>

          {(exportFormat === "plain" || exportFormat === "otpauth") && (
            <div className="flex items-center gap-2 rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-700 dark:text-amber-400">
              <AlertTriangle className="h-4 w-4 shrink-0" />
              TOTP secrets will be visible in the exported file.
            </div>
          )}

          {exportFormat === "encrypted" && (
            <Input id="export-password" type="password" required label="Export Password"
              value={exportPassword} onChange={(e) => setExportPassword(e.target.value)}
              autoComplete="new-password" autoFocus />
          )}

          <p className="text-muted-foreground text-xs">{entries.length} entries will be exported.</p>

          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" size="sm" onClick={() => setShowExportDialog(false)}>Cancel</Button>
            <Button type="submit" size="sm" disabled={exporting || (exportFormat === "encrypted" && !exportPassword)}>
              {exporting ? "Exporting..." : "Export"}
            </Button>
          </div>
        </form>
      </Dialog>

      {/* Encrypted import password dialog */}
      <Dialog open={showImportDialog} onClose={() => setShowImportDialog(false)} title="Decrypt Import">
        <form onSubmit={(e) => { e.preventDefault(); void handleDecryptImport(); }} className="space-y-4">
          <p className="text-muted-foreground text-sm">This file is encrypted. Enter the password used during export.</p>
          <Input id="import-password" type="password" required label="Password"
            value={importPassword} onChange={(e) => setImportPassword(e.target.value)}
            autoComplete="current-password" autoFocus />
          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" size="sm" onClick={() => setShowImportDialog(false)}>Cancel</Button>
            <Button type="submit" size="sm" disabled={importing || !importPassword}>
              {importing ? "Decrypting..." : "Decrypt"}
            </Button>
          </div>
        </form>
      </Dialog>
    </div>
  );
}
