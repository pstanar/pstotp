import { useState, useEffect, useCallback } from "react";
import { startRegistration, type RegistrationResponseJSON } from "@simplewebauthn/browser";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog } from "@/components/ui/dialog";
import {
  beginRegistration,
  completeRegistration,
  listCredentials,
  renameCredential,
  revokeCredential,
} from "@/features/webauthn/api/webauthn-api";
import type { WebAuthnCredentialInfo } from "@/types/api-types";
import { Key, Pencil, Trash2, Plus } from "lucide-react";

export function WebAuthnManagement() {
  const [credentials, setCredentials] = useState<WebAuthnCredentialInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [registering, setRegistering] = useState(false);
  const [nameDialogOpen, setNameDialogOpen] = useState(false);
  const [pendingAttResponse, setPendingAttResponse] = useState<RegistrationResponseJSON | null>(null);
  const [pendingCeremonyId, setPendingCeremonyId] = useState<string | null>(null);
  const [friendlyName, setFriendlyName] = useState("");
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameValue, setRenameValue] = useState("");
  const [confirmRevokeId, setConfirmRevokeId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const loadCredentials = useCallback(async () => {
    try {
      const result = await listCredentials();
      setCredentials(result.credentials);
    } catch {
      setError("Failed to load passkeys.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadCredentials();
  }, [loadCredentials]);

  const handleRegister = async () => {
    setError(null);
    setRegistering(true);
    try {
      const { ceremonyId, publicKeyOptions } = await beginRegistration();
      const attResp = await startRegistration({ optionsJSON: publicKeyOptions });
      setPendingAttResponse(attResp);
      setPendingCeremonyId(ceremonyId);
      setFriendlyName("");
      setNameDialogOpen(true);
    } catch (err) {
      if (err instanceof Error && err.name === "NotAllowedError") {
        setError("Registration was cancelled.");
      } else {
        setError("Failed to register passkey.");
      }
    } finally {
      setRegistering(false);
    }
  };

  const handleCompleteRegistration = async () => {
    if (!pendingCeremonyId || !pendingAttResponse) return;
    setError(null);
    try {
      await completeRegistration(pendingCeremonyId, friendlyName || "Passkey", pendingAttResponse);
      setNameDialogOpen(false);
      setPendingAttResponse(null);
      setPendingCeremonyId(null);
      await loadCredentials();
    } catch {
      setError("Failed to save passkey.");
    }
  };

  const handleRename = async () => {
    if (!renamingId || !renameValue.trim()) return;
    setSaving(true);
    try {
      await renameCredential(renamingId, renameValue.trim());
      setRenamingId(null);
      await loadCredentials();
    } catch {
      setError("Failed to rename passkey.");
    } finally {
      setSaving(false);
    }
  };

  const handleRevoke = async (id: string) => {
    setSaving(true);
    try {
      await revokeCredential(id);
      setConfirmRevokeId(null);
      await loadCredentials();
    } catch {
      setError("Failed to revoke passkey.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div>
      <label className="text-sm font-medium">Passkeys & Security Keys</label>
      <p className="text-muted-foreground mt-0.5 mb-3 text-sm">
        Use passkeys for passwordless sign-in or as a second factor for account recovery.
      </p>

      {error && <p className="text-destructive mb-2 text-sm">{error}</p>}

      {loading ? (
        <p className="text-muted-foreground text-sm">Loading...</p>
      ) : (
        <>
          {credentials.length > 0 && (
            <div className="mb-3 space-y-2">
              {credentials.map((cred) => (
                <div key={cred.id} className="border-border flex items-center justify-between rounded-md border p-3">
                  <div className="flex items-center gap-2.5 min-w-0">
                    <Key className="text-muted-foreground h-4 w-4 shrink-0" />
                    <div className="min-w-0">
                      <p className="text-sm font-medium truncate">{cred.friendlyName || "Passkey"}</p>
                      <p className="text-muted-foreground text-xs">
                        Added {new Date(cred.createdAt).toLocaleDateString()}
                        {cred.lastUsedAt && ` · Last used ${new Date(cred.lastUsedAt).toLocaleDateString()}`}
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center gap-1 shrink-0">
                    <button
                      onClick={() => { setRenamingId(cred.id); setRenameValue(cred.friendlyName || ""); }}
                      className="text-muted-foreground hover:text-foreground rounded-md p-2 transition-colors"
                      title="Rename"
                    >
                      <Pencil className="h-3.5 w-3.5" />
                    </button>
                    <button
                      onClick={() => setConfirmRevokeId(cred.id)}
                      className="text-muted-foreground hover:text-destructive rounded-md p-2 transition-colors"
                      title="Revoke"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}

          <Button
            variant="secondary"
            size="sm"
            onClick={handleRegister}
            disabled={registering}
          >
            <Plus className="mr-1.5 h-3.5 w-3.5" />
            {registering ? "Waiting for authenticator..." : "Add Passkey"}
          </Button>
        </>
      )}

      {/* Name dialog after browser registration */}
      <Dialog open={nameDialogOpen} onClose={() => setNameDialogOpen(false)} title="Name Your Passkey">
        <form onSubmit={(e) => { e.preventDefault(); void handleCompleteRegistration(); }} className="space-y-4">
          <Input
            id="passkey-name"
            type="text"
            label="Friendly Name"
            value={friendlyName}
            onChange={(e) => setFriendlyName(e.target.value)}
            placeholder="e.g. MacBook Touch ID, YubiKey"
            autoFocus
          />
          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" size="sm" onClick={() => setNameDialogOpen(false)}>Cancel</Button>
            <Button type="submit" size="sm">Save</Button>
          </div>
        </form>
      </Dialog>

      {/* Rename dialog */}
      <Dialog open={renamingId !== null} onClose={() => setRenamingId(null)} title="Rename Passkey">
        <form onSubmit={(e) => { e.preventDefault(); void handleRename(); }} className="space-y-4">
          <Input
            id="rename-passkey"
            type="text"
            label="New Name"
            value={renameValue}
            onChange={(e) => setRenameValue(e.target.value)}
            autoFocus
          />
          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" size="sm" onClick={() => setRenamingId(null)} disabled={saving}>Cancel</Button>
            <Button type="submit" size="sm" disabled={saving}>{saving ? "Renaming..." : "Rename"}</Button>
          </div>
        </form>
      </Dialog>

      {/* Revoke confirmation */}
      <Dialog open={confirmRevokeId !== null} onClose={() => setConfirmRevokeId(null)} title="Revoke Passkey">
        <p className="text-sm mb-4">
          This passkey will be permanently revoked. You won't be able to use it to sign in.
        </p>
        <div className="flex justify-end gap-2">
          <Button variant="secondary" size="sm" onClick={() => setConfirmRevokeId(null)} disabled={saving}>Cancel</Button>
          <Button variant="destructive" size="sm" onClick={() => confirmRevokeId && void handleRevoke(confirmRevokeId)} disabled={saving}>
            {saving ? "Revoking..." : "Revoke"}
          </Button>
        </div>
      </Dialog>
    </div>
  );
}
