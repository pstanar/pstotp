import { useState, useEffect, useCallback } from "react";
import { Monitor, Smartphone, Check, Clock, X, RefreshCw, ShieldOff } from "lucide-react";
import { Button } from "@/components/ui/button";
import { fetchDevices, approveDevice, rejectDevice, revokeDevice } from "@/features/devices/api/devices-api";
import { useVaultStore } from "@/stores/useVaultStore";
import { importEcdhPublicKey, packEcdhDeviceEnvelope, fromBase64 } from "@/lib/crypto";
import type { DeviceInfo } from "@/types/api-types";

export function DevicesPanel() {
  const [devices, setDevices] = useState<DeviceInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [actionInProgress, setActionInProgress] = useState<string | null>(null);
  const vaultKey = useVaultStore((s) => s.vaultKey);

  const loadDevices = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const response = await fetchDevices();
      setDevices(response.devices);
    } catch {
      setError("Failed to load devices.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadDevices();
  }, [loadDevices]);

  const handleApprove = async (device: DeviceInfo) => {
    setActionError(null);
    setActionInProgress(device.deviceId);
    try {
      if (!vaultKey) throw new Error("Vault is locked");
      if (!device.devicePublicKey) throw new Error("Device has no public key");

      // Import the pending device's ECDH public key
      const recipientPubKey = await importEcdhPublicKey(fromBase64(device.devicePublicKey));

      // ECDH: generate ephemeral key, derive shared secret, encrypt VaultKey
      const { ciphertext, nonce } = await packEcdhDeviceEnvelope(vaultKey, recipientPubKey);

      await approveDevice(device.deviceId, device.approvalRequestId!, {
        ciphertext,
        nonce,
        version: 1,
      });
      await loadDevices();
    } catch {
      setActionError("Failed to approve device.");
    } finally {
      setActionInProgress(null);
    }
  };

  const handleReject = async (deviceId: string) => {
    setActionError(null);
    setActionInProgress(deviceId);
    try {
      await rejectDevice(deviceId);
      await loadDevices();
    } catch {
      setActionError("Failed to reject device.");
    } finally {
      setActionInProgress(null);
    }
  };

  const handleRevoke = async (deviceId: string) => {
    setActionError(null);
    setActionInProgress(deviceId);
    try {
      await revokeDevice(deviceId);
      await loadDevices();
    } catch {
      setActionError("Failed to revoke device.");
    } finally {
      setActionInProgress(null);
    }
  };

  const approvedDevices = devices.filter((d) => d.status === "approved");
  const pendingDevices = devices.filter((d) => d.status === "pending");
  const revokedDevices = devices.filter((d) => d.status === "revoked");

  return (
    <div>
      <div className="mb-4 flex items-center justify-between">
        <h2 className="text-sm font-semibold">Your Devices</h2>
        <button
          onClick={() => void loadDevices()}
          disabled={loading}
          className="text-muted-foreground hover:text-foreground p-1 disabled:opacity-50"
          title="Refresh"
        >
          <RefreshCw className={`h-4 w-4 ${loading ? "animate-spin" : ""}`} />
        </button>
      </div>

      {error && (
        <div className="bg-destructive/10 text-destructive mb-4 rounded-md px-4 py-2 text-sm">{error}</div>
      )}
      {actionError && (
        <div className="bg-destructive/10 text-destructive mb-4 rounded-md px-4 py-2 text-sm">{actionError}</div>
      )}

      {loading && devices.length === 0 ? (
        <p className="text-muted-foreground text-center py-8">Loading devices...</p>
      ) : devices.length === 0 ? (
        <p className="text-muted-foreground text-center py-8">No devices registered.</p>
      ) : (
        <div className="space-y-6">
          {pendingDevices.length > 0 && (
            <section>
              <h3 className="text-xs font-semibold mb-2 text-amber-600 dark:text-amber-400 flex items-center gap-1.5">
                <Clock className="h-3.5 w-3.5" />
                Pending Approval ({pendingDevices.length})
              </h3>
              <div className="space-y-2">
                {pendingDevices.map((device) => (
                  <div
                    key={device.deviceId}
                    className="border-yellow-300 bg-yellow-50 dark:border-yellow-800 dark:bg-yellow-950/30 flex flex-col gap-2 rounded-lg border p-3 sm:flex-row sm:items-center sm:justify-between"
                  >
                    <div className="flex items-center gap-3 min-w-0">
                      <DeviceIcon platform={device.platform} />
                      <div className="min-w-0">
                        <p className="text-sm font-medium truncate">{device.deviceName}</p>
                        <p className="text-muted-foreground text-xs">
                          Requested {device.requestedAt ? new Date(device.requestedAt).toLocaleString() : "recently"}
                        </p>
                      </div>
                    </div>
                    <div className="flex items-center gap-2 shrink-0">
                      <Button size="sm" onClick={() => void handleApprove(device)} disabled={actionInProgress !== null}>
                        {actionInProgress === device.deviceId ? "Approving..." : "Approve"}
                      </Button>
                      <Button variant="destructive" size="sm" onClick={() => void handleReject(device.deviceId)} disabled={actionInProgress !== null}>
                        Reject
                      </Button>
                    </div>
                  </div>
                ))}
              </div>
            </section>
          )}

          {approvedDevices.length > 0 && (
            <section>
              <h3 className="text-xs font-semibold mb-2 text-emerald-600 dark:text-emerald-400 flex items-center gap-1.5">
                <Check className="h-3.5 w-3.5" />
                Approved ({approvedDevices.length})
              </h3>
              <div className="space-y-2">
                {approvedDevices.map((device) => (
                  <div
                    key={device.deviceId}
                    className="border-border flex items-center justify-between rounded-lg border p-3"
                  >
                    <div className="flex items-center gap-3">
                      <DeviceIcon platform={device.platform} />
                      <div>
                        <p className="text-sm font-medium">{device.deviceName}</p>
                        <p className="text-muted-foreground text-xs">
                          {device.platform}
                          {device.approvedAt && ` · Approved ${new Date(device.approvedAt).toLocaleDateString()}`}
                        </p>
                      </div>
                    </div>
                    <button
                      onClick={() => void handleRevoke(device.deviceId)}
                      disabled={actionInProgress !== null}
                      className="text-muted-foreground hover:text-destructive p-2.5 transition-colors disabled:opacity-50"
                      title="Revoke device"
                    >
                      <ShieldOff className="h-4 w-4" />
                    </button>
                  </div>
                ))}
              </div>
            </section>
          )}

          {revokedDevices.length > 0 && (
            <section>
              <h3 className="text-xs font-semibold mb-2 text-muted-foreground flex items-center gap-1.5">
                <X className="h-3.5 w-3.5" />
                Revoked ({revokedDevices.length})
              </h3>
              <div className="space-y-2">
                {revokedDevices.map((device) => (
                  <div
                    key={device.deviceId}
                    className="border-border flex items-center justify-between rounded-lg border p-3 opacity-60"
                  >
                    <div className="flex items-center gap-3">
                      <DeviceIcon platform={device.platform} />
                      <div>
                        <p className="text-sm font-medium">{device.deviceName}</p>
                        <p className="text-muted-foreground text-xs">{device.platform}</p>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </section>
          )}
        </div>
      )}
    </div>
  );
}

function DeviceIcon({ platform }: { platform: string }) {
  const p = platform.toLowerCase();
  if (p === "android" || p === "ios") {
    return <Smartphone className="text-muted-foreground h-5 w-5 shrink-0" />;
  }
  return <Monitor className="text-muted-foreground h-5 w-5 shrink-0" />;
}
