import { useState, useEffect, useCallback } from "react";
import { Search, X, Shield, ShieldOff, KeyRound, Trash2, RefreshCw, ChevronDown, ChevronUp } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog } from "@/components/ui/dialog";
import { useToast } from "@/hooks/use-toast";
import { BackupSection } from "./backup-section";
import {
  listUsers,
  getUserDetail,
  disableUser,
  enableUser,
  forcePasswordReset,
  deleteUser,
  cancelRecoverySession,
  type AdminUser,
  type AdminDevice,
  type AdminRecoverySession,
} from "@/features/admin/api/admin-api";

export function AdminPage() {
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [totalCount, setTotalCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [expandedDevices, setExpandedDevices] = useState<AdminDevice[]>([]);
  const [expandedRecoverySessions, setExpandedRecoverySessions] = useState<AdminRecoverySession[]>([]);
  const [confirmDelete, setConfirmDelete] = useState<AdminUser | null>(null);
  const [actionLoading, setActionLoading] = useState(false);
  const { toast } = useToast();

  const loadUsers = useCallback(async () => {
    setLoading(true);
    try {
      const result = await listUsers(search || undefined);
      setUsers(result.users);
      setTotalCount(result.totalCount);
    } catch {
      toast("Failed to load users", "error");
    } finally {
      setLoading(false);
    }
  }, [search, toast]);

  // Debounce search
  useEffect(() => {
    const timer = setTimeout(() => void loadUsers(), 300);
    return () => clearTimeout(timer);
  }, [loadUsers]);

  const handleExpand = async (userId: string) => {
    if (expandedId === userId) {
      setExpandedId(null);
      return;
    }
    try {
      const detail = await getUserDetail(userId);
      setExpandedDevices(detail.devices);
      setExpandedRecoverySessions(detail.recoverySessions ?? []);
      setExpandedId(userId);
    } catch {
      toast("Failed to load user details", "error");
    }
  };

  const handleDisable = async (user: AdminUser) => {
    setActionLoading(true);
    try {
      await disableUser(user.id);
      toast(`${user.email} disabled`);
      await loadUsers();
    } catch {
      toast("Failed to disable user", "error");
    } finally {
      setActionLoading(false);
    }
  };

  const handleEnable = async (user: AdminUser) => {
    setActionLoading(true);
    try {
      await enableUser(user.id);
      toast(`${user.email} enabled`);
      await loadUsers();
    } catch {
      toast("Failed to enable user", "error");
    } finally {
      setActionLoading(false);
    }
  };

  const handleForceReset = async (user: AdminUser) => {
    setActionLoading(true);
    try {
      await forcePasswordReset(user.id);
      toast(`Password reset required for ${user.email}`);
      await loadUsers();
    } catch {
      toast("Failed to set password reset", "error");
    } finally {
      setActionLoading(false);
    }
  };

  const handleDelete = async (user: AdminUser) => {
    setActionLoading(true);
    try {
      await deleteUser(user.id);
      toast(`${user.email} deleted`);
      setConfirmDelete(null);
      setExpandedId(null);
      await loadUsers();
    } catch {
      toast("Failed to delete user", "error");
    } finally {
      setActionLoading(false);
    }
  };

  return (
    <div>
      <div className="mb-4 flex items-center gap-3">
        <span className="text-muted-foreground text-sm">{totalCount} users</span>
        <div className="ml-auto">
          <button onClick={() => void loadUsers()} disabled={loading}
            className="text-muted-foreground hover:text-foreground p-2 disabled:opacity-50">
            <RefreshCw className={`h-4 w-4 ${loading ? "animate-spin" : ""}`} />
          </button>
        </div>
      </div>

      {/* Search */}
      <div className="border-input bg-background relative mb-4 flex items-center rounded-md border shadow-sm">
        <Search className="text-muted-foreground absolute left-3 h-4 w-4" />
        <input
          type="text"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search users..."
          className="bg-transparent w-full py-2 pl-9 pr-8 text-sm outline-none"
        />
        {search && (
          <button
            onClick={() => setSearch("")}
            className="text-muted-foreground hover:text-foreground absolute right-2 p-0.5"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        )}
      </div>

      {loading && users.length === 0 ? (
        <p className="text-muted-foreground text-center py-8">Loading users...</p>
      ) : users.length === 0 ? (
        <p className="text-muted-foreground text-center py-8">No users found.</p>
      ) : (
        <div className="space-y-2">
          {users.map((user) => (
            <div key={user.id} className="border-border rounded-lg border">
              <div
                className="flex cursor-pointer items-center justify-between p-3 hover:bg-accent/30"
                onClick={() => void handleExpand(user.id)}
              >
                <div className="flex items-center gap-3 min-w-0">
                  <div className={`h-2 w-2 shrink-0 rounded-full ${user.disabledAt ? "bg-destructive" : "bg-green-500"}`} />
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <p className="text-sm font-medium truncate">{user.email}</p>
                      {user.role === "Admin" && (
                        <span className="rounded bg-primary/10 px-1.5 py-0.5 text-[10px] font-semibold text-primary">ADMIN</span>
                      )}
                      {user.disabledAt && (
                        <span className="rounded bg-destructive/10 px-1.5 py-0.5 text-[10px] font-semibold text-destructive">DISABLED</span>
                      )}
                      {user.forcePasswordReset && (
                        <span className="rounded bg-amber-500/10 px-1.5 py-0.5 text-[10px] font-semibold text-amber-600 dark:text-amber-400">RESET</span>
                      )}
                    </div>
                    <p className="text-muted-foreground text-xs">
                      {user.entryCount} entries · {user.deviceCount} devices · {user.credentialCount} passkeys
                      {user.lastLoginAt && ` · Last login ${new Date(user.lastLoginAt).toLocaleDateString()}`}
                    </p>
                  </div>
                </div>
                <div className="shrink-0">
                  {expandedId === user.id ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                </div>
              </div>

              {/* Expanded detail */}
              {expandedId === user.id && (
                <div className="border-t px-3 py-3 space-y-3">
                  {/* Actions */}
                  <div className="flex flex-wrap gap-2">
                    {user.disabledAt ? (
                      <Button size="sm" variant="secondary" onClick={() => void handleEnable(user)} disabled={actionLoading}>
                        <Shield className="mr-1.5 h-3.5 w-3.5" /> Enable
                      </Button>
                    ) : (
                      <Button size="sm" variant="secondary" onClick={() => void handleDisable(user)} disabled={actionLoading}>
                        <ShieldOff className="mr-1.5 h-3.5 w-3.5" /> Disable
                      </Button>
                    )}
                    {!user.forcePasswordReset && (
                      <Button size="sm" variant="secondary" onClick={() => void handleForceReset(user)} disabled={actionLoading}>
                        <KeyRound className="mr-1.5 h-3.5 w-3.5" /> Force Password Reset
                      </Button>
                    )}
                    <Button size="sm" variant="destructive" onClick={() => setConfirmDelete(user)} disabled={actionLoading}>
                      <Trash2 className="mr-1.5 h-3.5 w-3.5" /> Delete
                    </Button>
                  </div>

                  {/* Devices */}
                  {expandedDevices.length > 0 && (
                    <div>
                      <p className="text-xs font-semibold text-muted-foreground mb-1.5">Devices</p>
                      <div className="space-y-1">
                        {expandedDevices.map((d) => (
                          <div key={d.id} className="flex items-center justify-between rounded bg-muted/50 px-2.5 py-1.5 text-xs">
                            <span className="font-medium">{d.deviceName}</span>
                            <span className="text-muted-foreground">
                              {d.platform} · {d.status}
                              {d.lastSeenAt && ` · ${new Date(d.lastSeenAt).toLocaleDateString()}`}
                            </span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Recovery Sessions */}
                  {expandedRecoverySessions.length > 0 && (
                    <div>
                      <p className="text-xs font-semibold text-muted-foreground mb-1.5">Active Recovery Sessions</p>
                      <div className="space-y-1">
                        {expandedRecoverySessions.map((s) => (
                          <div key={s.id} className="flex items-center justify-between rounded bg-amber-500/10 px-2.5 py-1.5 text-xs">
                            <span>
                              <span className="font-medium">{s.status}</span>
                              <span className="text-muted-foreground"> · Available after {new Date(s.releaseEarliestAt).toLocaleString()}</span>
                              <span className="text-muted-foreground"> · Expires {new Date(s.expiresAt).toLocaleString()}</span>
                            </span>
                            <button
                              onClick={async (e) => {
                                e.stopPropagation();
                                try {
                                  await cancelRecoverySession(user.id, s.id);
                                  setExpandedRecoverySessions((prev) => prev.filter((rs) => rs.id !== s.id));
                                  toast("Recovery session cancelled", "success");
                                } catch {
                                  toast("Failed to cancel session", "error");
                                }
                              }}
                              className="rounded bg-amber-600 px-2 py-0.5 text-white text-xs font-medium hover:bg-amber-700 transition-colors"
                            >
                              Cancel
                            </button>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Info */}
                  <p className="text-muted-foreground text-xs">
                    Created {new Date(user.createdAt).toLocaleString()} · ID: {user.id}
                  </p>
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      <BackupSection />

      {/* Delete confirmation */}
      <Dialog open={confirmDelete !== null} onClose={() => setConfirmDelete(null)} title="Delete User">
        {confirmDelete && (
          <div className="space-y-4">
            <p className="text-sm">
              Permanently delete <strong>{confirmDelete.email}</strong> and all their data?
              This cannot be undone.
            </p>
            <div className="flex justify-end gap-2">
              <Button variant="secondary" size="sm" onClick={() => setConfirmDelete(null)} disabled={actionLoading}>Cancel</Button>
              <Button variant="destructive" size="sm" onClick={() => void handleDelete(confirmDelete)} disabled={actionLoading}>
                {actionLoading ? "Deleting..." : "Delete"}
              </Button>
            </div>
          </div>
        )}
      </Dialog>
    </div>
  );
}
