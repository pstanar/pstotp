import { useState, useEffect, useCallback, useMemo } from "react";
import { useVaultStore } from "@/stores/useVaultStore";
import { useAuthStore } from "@/stores/useAuthStore";
import { useSettingsStore } from "@/stores/useSettingsStore";
import { withBasePath } from "@/lib/base-path";
import { useInactivityLock } from "@/hooks/use-inactivity-lock";
import { encryptEntry } from "@/features/vault/utils/vault-crypto";
import { buildOtpauthUri } from "@/features/vault/utils/otpauth-uri";
import { upsertEntry, deleteEntry as deleteEntryApi, reorderEntries } from "@/features/vault/api/vault-api";
import { getSystemInfo, shutdownServer, type SystemInfo } from "@/lib/system-api";
import {
  DndContext,
  closestCenter,
  KeyboardSensor,
  PointerSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core";
import {
  SortableContext,
  sortableKeyboardCoordinates,
  verticalListSortingStrategy,
  rectSortingStrategy,
} from "@dnd-kit/sortable";
import { VaultHeader } from "./vault-header";
import { SortableCard } from "./sortable-card";
import { SortableGridTile } from "./sortable-grid-tile";
import { TotpGridDetail } from "./totp-grid-detail";
import { EntryContextMenu } from "./entry-context-menu";
import { QrCodeDialog } from "./qr-code-dialog";
import { AddAccountDialog } from "./add-account-dialog";
import { EditEntryDialog } from "./edit-entry-dialog";
import { Dialog } from "@/components/ui/dialog";
import { fetchAndDecryptVault } from "@/features/auth/utils/vault-unlock";
import { useToast } from "@/hooks/use-toast";
import { recordUse, forgetEntry } from "@/lib/usage-tracker";
import {
  getSortMode,
  setSortMode as persistSortMode,
  getSortReversed,
  setSortReversed as persistSortReversed,
  sortEntries,
  type SortMode,
} from "@/lib/sort-mode";
import { Plus, Power } from "lucide-react";
import { useNavigate } from "@tanstack/react-router";
import type { VaultEntry } from "@/types/vault-types";

type ViewLayout = "list" | "grid";
const LAYOUT_KEY = "pstotp-layout";

export function VaultPage() {
  const { isUnlocked, vaultKey, entries, addEntry, removeEntry, updateEntry } = useVaultStore();
  const [showAddDialog, setShowAddDialog] = useState(false);
  const [editingEntry, setEditingEntry] = useState<VaultEntry | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const lastSyncAt = useVaultStore((s) => s.lastSyncAt);
  const setEntries = useVaultStore((s) => s.setEntries);
  const [searchQuery, setSearchQuery] = useState("");
  const [showSearch, setShowSearch] = useState(false);
  const [layout, setLayout] = useState<ViewLayout>(
    () => (localStorage.getItem(LAYOUT_KEY) as ViewLayout) || "list",
  );
  const [sortMode, setSortModeState] = useState<SortMode>(() => getSortMode());
  const onChangeSortMode = useCallback((mode: SortMode) => {
    setSortModeState(mode);
    persistSortMode(mode);
  }, []);
  const [sortReversed, setSortReversedState] = useState<boolean>(() => getSortReversed());
  const onToggleSortReversed = useCallback(() => {
    setSortReversedState((prev) => {
      const next = !prev;
      persistSortReversed(next);
      return next;
    });
  }, []);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [gridMenuPos, setGridMenuPos] = useState<{ x: number; y: number } | null>(null);
  const [gridMenuEntryId, setGridMenuEntryId] = useState<string | null>(null);
  const [showQr, setShowQr] = useState(false);
  const [qrEntryId, setQrEntryId] = useState<string | null>(null);
  const [systemInfo, setSystemInfo] = useState<SystemInfo | null>(null);
  const [showShutdownDialog, setShowShutdownDialog] = useState(false);
  const [isShutdown, setIsShutdown] = useState(false);
  const [shuttingDown, setShuttingDown] = useState(false);
  const { toast } = useToast();
  const email = useAuthStore((s) => s.email);
  const lock = useVaultStore((s) => s.lock);
  const navigate = useNavigate();

  // Fetch system info (shutdown availability)
  useEffect(() => {
    getSystemInfo().then(setSystemInfo).catch(() => {});
  }, []);

  // Auto-lock after the configured inactivity window. 0 ms means "Never".
  const lockTimeoutMs = useSettingsStore((s) => s.lockTimeoutMs);
  useInactivityLock(
    () => { lock(); void navigate({ to: "/login" }); },
    lockTimeoutMs,
    isUnlocked && lockTimeoutMs > 0,
  );

  useEffect(() => {
    document.title = email ? `PsTotp - ${email}` : "PsTotp";
    return () => { document.title = "PsTotp"; };
  }, [email]);

  // Auto-select first entry in grid view
  useEffect(() => {
    if (layout === "grid" && entries.length > 0 && !entries.find((e) => e.id === selectedId)) {
      setSelectedId(entries[0].id);
    }
  }, [layout, entries, selectedId]);

  const switchLayout = (l: ViewLayout) => {
    setLayout(l);
    localStorage.setItem(LAYOUT_KEY, l);
  };

  const handleGridCopyCode = useCallback(async () => {
    const entry = entries.find((e) => e.id === gridMenuEntryId);
    if (!entry) return;
    const { generateTotp } = await import("@/features/vault/utils/totp");
    const code = generateTotp(entry.secret, entry.algorithm, entry.digits, entry.period);
    await navigator.clipboard.writeText(code);
    recordUse(entry.id);
    toast("Code copied");
  }, [entries, gridMenuEntryId, toast]);

  const handleGridCopySecret = useCallback(async () => {
    const entry = entries.find((e) => e.id === gridMenuEntryId);
    if (!entry) return;
    await navigator.clipboard.writeText(entry.secret);
    toast("Secret key copied");
  }, [entries, gridMenuEntryId, toast]);

  const handleRefresh = useCallback(async () => {
    if (!vaultKey || refreshing) return;
    setRefreshing(true);
    try {
      const freshEntries = await fetchAndDecryptVault(vaultKey);
      setEntries(freshEntries);
    } catch {
      toast("Failed to refresh vault", "error");
    } finally {
      setRefreshing(false);
    }
  }, [vaultKey, refreshing, setEntries, toast]);

  const handleShutdown = useCallback(async () => {
    setShuttingDown(true);
    try {
      await shutdownServer();
      setShowShutdownDialog(false);
      setIsShutdown(true);
      window.close();
    } catch {
      toast("Failed to shut down application", "error");
      setShuttingDown(false);
    }
  }, [toast]);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  const handleDragEnd = useCallback((event: DragEndEvent) => {
    if (sortMode !== "manual") return;
    const { active, over } = event;
    if (!over || active.id === over.id) return;

    const oldIndex = entries.findIndex((e) => e.id === active.id);
    const newIndex = entries.findIndex((e) => e.id === over.id);
    if (oldIndex < 0 || newIndex < 0) return;

    const reordered = [...entries];
    const [moved] = reordered.splice(oldIndex, 1);
    reordered.splice(newIndex, 0, moved);
    const previousEntries = entries;
    setEntries(reordered);

    // Sync to server with rollback on failure
    reorderEntries(reordered.map(e => e.id)).catch(() => {
      setEntries(previousEntries);
      toast("Failed to save order", "error");
    });
  }, [entries, setEntries, toast, sortMode]);

  const query = searchQuery.toLowerCase();
  const filteredEntries = useMemo(() => {
    const filtered = query
      ? entries.filter((e) =>
          e.issuer.toLowerCase().includes(query) ||
          e.accountName.toLowerCase().includes(query))
      : entries;
    return sortEntries(filtered, sortMode, sortReversed);
  }, [entries, query, sortMode, sortReversed]);

  useEffect(() => {
    if (!isUnlocked) {
      void navigate({ to: "/login" });
    }
  }, [isUnlocked, navigate]);

  if (!isUnlocked) {
    return null;
  }

  if (isShutdown) {
    return (
      <div className="flex min-h-[70vh] items-center justify-center">
        <div className="text-center space-y-4 px-4">
          <div className="bg-muted mx-auto flex h-16 w-16 items-center justify-center rounded-full">
            <Power className="h-8 w-8 text-muted-foreground" />
          </div>
          <h1 className="text-xl font-semibold">Application Shut Down</h1>
          <p className="text-muted-foreground text-sm max-w-sm mx-auto">
            PsTotp has been shut down successfully. You can now close this window.
          </p>
        </div>
      </div>
    );
  }

  const handleAddEntry = async (plaintext: {
    issuer: string;
    accountName: string;
    secret: string;
    algorithm: string;
    digits: number;
    period: number;
  }) => {
    try {
      if (!vaultKey) throw new Error("Vault key not available");
      const id = crypto.randomUUID();
      const payload = await encryptEntry(vaultKey, plaintext, id);
      const response = await upsertEntry(id, payload, 0);
      addEntry({ ...plaintext, id, version: response.entryVersion });
      toast("Account added");
    } catch {
      toast("Failed to add account", "error");
    }
  };

  const handleEditEntry = async (id: string, updates: { issuer: string; accountName: string; icon?: string }) => {
    const entry = entries.find((e) => e.id === id);
    if (!entry) return;

    const updated = { ...entry, ...updates };
    try {
      if (!vaultKey) throw new Error("Vault key not available");
      const plaintext = {
        issuer: updated.issuer,
        accountName: updated.accountName,
        secret: updated.secret,
        algorithm: updated.algorithm,
        digits: updated.digits,
        period: updated.period,
        icon: updated.icon,
      };
      const payload = await encryptEntry(vaultKey, plaintext, id);
      const response = await upsertEntry(id, payload, entry.version);
      updateEntry(id, { ...updates, version: response.entryVersion });
    } catch {
      toast("Failed to save changes", "error");
    }
  };

  const handleDeleteEntry = async (id: string) => {
    try {
      await deleteEntryApi(id);
      removeEntry(id);
      forgetEntry(id);
      if (selectedId === id) setSelectedId(null);
    } catch {
      toast("Failed to delete entry", "error");
    }
  };

  const selectedEntry = filteredEntries.find((e) => e.id === selectedId);
  const gridMenuEntry = entries.find((e) => e.id === gridMenuEntryId);
  const qrEntry = entries.find((e) => e.id === qrEntryId);

  return (
    <div className="mx-auto max-w-2xl px-4 py-6 pb-24">
      <VaultHeader
        layout={layout}
        onSwitchLayout={switchLayout}
        showSearch={showSearch}
        searchQuery={searchQuery}
        onToggleSearch={() => { setShowSearch(!showSearch); if (showSearch) setSearchQuery(""); }}
        onSearchChange={setSearchQuery}
        sortMode={sortMode}
        onChangeSortMode={onChangeSortMode}
        sortReversed={sortReversed}
        onToggleSortReversed={onToggleSortReversed}
        lastSyncAt={lastSyncAt}
        refreshing={refreshing}
        onRefresh={() => void handleRefresh()}
        onRequestShutdown={systemInfo?.shutdownAvailable ? () => setShowShutdownDialog(true) : undefined}
      />

      {entries.length === 0 ? (
        <div className="text-center py-16 space-y-6">
          <div className="bg-primary/10 mx-auto flex h-20 w-20 items-center justify-center rounded-full">
            <img src={withBasePath("/favicon.svg")} alt="" className="h-10 w-10" />
          </div>
          <div>
            <p className="text-lg font-semibold">Welcome to PsTotp</p>
            <p className="text-muted-foreground mx-auto mt-2 max-w-xs text-sm">
              Your TOTP vault is empty. Add an account by scanning a QR code, uploading an image, or entering the secret key manually.
            </p>
          </div>
          <button
            onClick={() => setShowAddDialog(true)}
            className="bg-primary text-primary-foreground hover:bg-primary/90 rounded-md px-6 py-3 text-sm font-medium shadow-sm transition-all active:scale-[0.98]"
          >
            Add Your First Account
          </button>
        </div>
      ) : filteredEntries.length === 0 ? (
        <div className="text-center py-20">
          <p className="text-muted-foreground">No matches for &ldquo;{searchQuery}&rdquo;</p>
        </div>
      ) : layout === "list" ? (
        <>
          <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
            <SortableContext items={filteredEntries.map(e => e.id)} strategy={verticalListSortingStrategy}>
              <div className="space-y-2">
                {filteredEntries.map((entry, i) => (
                  <div key={entry.id} className="vault-entry-animate" style={{ animationDelay: `${i * 50}ms` }}>
                    <SortableCard
                      entry={entry}
                      dragEnabled={sortMode === "manual"}
                      onEdit={() => setEditingEntry(entry)}
                      onDelete={() => void handleDeleteEntry(entry.id)}
                    />
                  </div>
                ))}
              </div>
            </SortableContext>
          </DndContext>
        </>
      ) : (
        <>
          {/* Grid view: expanded detail at top */}
          {selectedEntry && <TotpGridDetail entry={selectedEntry} />}

          {/* Grid of tiles */}
          <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
            <SortableContext items={filteredEntries.map(e => e.id)} strategy={rectSortingStrategy}>
              <div className="grid grid-cols-2 gap-1 sm:grid-cols-3 md:grid-cols-4">
                {filteredEntries.map((entry) => (
                  <SortableGridTile
                    key={entry.id}
                    entry={entry}
                    selected={entry.id === selectedId}
                    dragEnabled={sortMode === "manual"}
                    onSelect={() => setSelectedId(entry.id)}
                    onContextMenu={(e) => {
                      e.preventDefault();
                      setGridMenuEntryId(entry.id);
                      setGridMenuPos({ x: e.clientX, y: e.clientY });
                    }}
                  />
                ))}
              </div>
            </SortableContext>
          </DndContext>
        </>
      )}

      {/* Floating Add button — always reachable regardless of scroll position */}
      {entries.length > 0 && (
        <button
          onClick={() => setShowAddDialog(true)}
          className="bg-primary text-primary-foreground hover:bg-primary/90 fixed bottom-6 right-6 z-20 flex h-14 w-14 items-center justify-center rounded-full shadow-lg transition-transform active:scale-95"
          title="Add Account"
          aria-label="Add Account"
        >
          <Plus className="h-6 w-6" />
        </button>
      )}

      {/* Grid context menu */}
      {gridMenuPos && gridMenuEntry && (
        <EntryContextMenu
          x={gridMenuPos.x}
          y={gridMenuPos.y}
          onClose={() => { setGridMenuPos(null); setGridMenuEntryId(null); }}
          onCopyCode={handleGridCopyCode}
          onCopySecret={handleGridCopySecret}
          onShowQr={() => { setQrEntryId(gridMenuEntryId); setShowQr(true); }}
          onEdit={() => setEditingEntry(gridMenuEntry)}
          onDelete={() => handleDeleteEntry(gridMenuEntry.id)}
        />
      )}

      {/* Grid QR dialog */}
      {showQr && qrEntry && (
        <QrCodeDialog
          open={true}
          onClose={() => { setShowQr(false); setQrEntryId(null); }}
          uri={buildOtpauthUri(qrEntry)}
          title={`${qrEntry.issuer} — ${qrEntry.accountName}`}
        />
      )}

      <AddAccountDialog
        open={showAddDialog}
        onClose={() => setShowAddDialog(false)}
        onAdd={handleAddEntry}
      />

      {editingEntry && (
        <EditEntryDialog
          open={true}
          entry={editingEntry}
          onClose={() => setEditingEntry(null)}
          onSave={(updates) => handleEditEntry(editingEntry.id, updates)}
        />
      )}

      <Dialog open={showShutdownDialog} onClose={() => setShowShutdownDialog(false)} title="Shut Down Application?">
        <div className="space-y-4">
          <p className="text-sm text-muted-foreground">
            The PsTotp server will stop and the application will no longer be accessible until it is started again.
          </p>
          {systemInfo?.multiUser && (
            <p className="text-sm font-medium text-amber-600 dark:text-amber-400">
              This is a multi-user server. Other users may be affected by this action.
            </p>
          )}
          <div className="flex justify-end gap-3 pt-2">
            <button
              onClick={() => setShowShutdownDialog(false)}
              disabled={shuttingDown}
              className="rounded-md px-4 py-2 text-sm font-medium text-muted-foreground hover:text-foreground transition-colors"
            >
              Cancel
            </button>
            <button
              onClick={() => void handleShutdown()}
              disabled={shuttingDown}
              className="bg-destructive text-white hover:bg-destructive/90 rounded-md px-4 py-2 text-sm font-medium transition-colors disabled:opacity-50"
            >
              {shuttingDown ? "Shutting down..." : "Shut Down"}
            </button>
          </div>
        </div>
      </Dialog>
    </div>
  );
}
