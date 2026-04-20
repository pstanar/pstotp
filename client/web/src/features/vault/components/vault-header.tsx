import { apiClient } from "@/lib/api-client";
import { withBasePath } from "@/lib/base-path";
import { useAuthStore } from "@/stores/useAuthStore";
import { useVaultStore } from "@/stores/useVaultStore";
import { Lock, Shield, Settings, List, LayoutGrid, Search, X, RefreshCw, Power, ArrowUpDown, Check, ArrowDown, ArrowUp } from "lucide-react";
import { Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";
import type { SortMode } from "@/lib/sort-mode";

type ViewLayout = "list" | "grid";

interface VaultHeaderProps {
  layout: ViewLayout;
  onSwitchLayout: (layout: ViewLayout) => void;
  showSearch: boolean;
  searchQuery: string;
  onToggleSearch: () => void;
  onSearchChange: (query: string) => void;
  sortMode: SortMode;
  onChangeSortMode: (mode: SortMode) => void;
  sortReversed: boolean;
  onToggleSortReversed: () => void;
  lastSyncAt: string | null;
  refreshing: boolean;
  onRefresh: () => void;
  onRequestShutdown?: () => void;
}

const SORT_LABELS: Record<SortMode, string> = {
  manual: "Manual",
  alphabetical: "Alphabetical",
  lru: "Recently used",
  mfu: "Most used",
};

export function VaultHeader({
  layout,
  onSwitchLayout,
  showSearch,
  searchQuery,
  onToggleSearch,
  onSearchChange,
  sortMode,
  onChangeSortMode,
  sortReversed,
  onToggleSortReversed,
  lastSyncAt,
  refreshing,
  onRefresh,
  onRequestShutdown,
}: VaultHeaderProps) {
  const email = useAuthStore((s) => s.email);
  const logout = useAuthStore((s) => s.logout);
  const lock = useVaultStore((s) => s.lock);
  const navigate = useNavigate();

  const [sortOpen, setSortOpen] = useState(false);
  const sortMenuRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!sortOpen) return;
    const onClickOutside = (e: MouseEvent) => {
      if (sortMenuRef.current && !sortMenuRef.current.contains(e.target as Node)) {
        setSortOpen(false);
      }
    };
    document.addEventListener("mousedown", onClickOutside);
    return () => document.removeEventListener("mousedown", onClickOutside);
  }, [sortOpen]);

  return (
    <>
      <header className="mb-6 flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-3">
          <img src={withBasePath("/favicon.svg")} alt="" className="h-8 w-8 shrink-0" />
          <div>
            <h1 className="text-xl font-bold">PsTotp</h1>
            <div className="flex items-center gap-1.5">
              <p className="text-muted-foreground text-sm">{email}</p>
              <button
                onClick={onRefresh}
                disabled={refreshing}
                className="text-muted-foreground hover:text-foreground p-0.5 disabled:opacity-50"
                title={lastSyncAt ? `Last sync: ${new Date(lastSyncAt).toLocaleTimeString()}` : "Refresh"}
              >
                <RefreshCw className={`h-3 w-3 ${refreshing ? "animate-spin" : ""}`} />
              </button>
            </div>
          </div>
        </div>
        <div className="flex items-center gap-1">
          <div className="bg-muted mr-1 flex rounded-md p-0.5">
            <button
              onClick={() => onSwitchLayout("list")}
              className={`rounded p-1.5 ${layout === "list" ? "bg-background shadow-sm" : "text-muted-foreground"}`}
              title="List view"
            >
              <List className="h-4 w-4" />
            </button>
            <button
              onClick={() => onSwitchLayout("grid")}
              className={`rounded p-1.5 ${layout === "grid" ? "bg-background shadow-sm" : "text-muted-foreground"}`}
              title="Grid view"
            >
              <LayoutGrid className="h-4 w-4" />
            </button>
          </div>

          <div ref={sortMenuRef} className="relative">
            <button
              onClick={() => setSortOpen(!sortOpen)}
              className={`rounded-md p-2.5 ${sortMode !== "manual" ? "text-foreground" : "text-muted-foreground hover:text-foreground"}`}
              title={`Sort: ${SORT_LABELS[sortMode]}`}
            >
              <ArrowUpDown className="h-5 w-5" />
            </button>
            {sortOpen && (
              <div className="border-border bg-popover absolute right-0 top-full z-20 mt-1 min-w-[180px] rounded-md border py-1 shadow-md">
                {(Object.keys(SORT_LABELS) as SortMode[]).map((mode) => (
                  <button
                    key={mode}
                    onClick={() => { onChangeSortMode(mode); setSortOpen(false); }}
                    className="hover:bg-accent flex w-full items-center gap-2 px-3 py-1.5 text-left text-sm"
                  >
                    <Check className={`h-3.5 w-3.5 ${mode === sortMode ? "opacity-100" : "opacity-0"}`} />
                    {SORT_LABELS[mode]}
                  </button>
                ))}
                {/* Direction selector — disabled for MANUAL since the user's
                    own order has no natural direction. */}
                <div className="border-border my-1 border-t" />
                <button
                  onClick={() => { if (sortReversed) onToggleSortReversed(); setSortOpen(false); }}
                  disabled={sortMode === "manual"}
                  className="hover:bg-accent flex w-full items-center gap-2 px-3 py-1.5 text-left text-sm disabled:opacity-40 disabled:hover:bg-transparent"
                >
                  <ArrowDown className={`h-3.5 w-3.5 ${!sortReversed ? "text-primary" : "text-muted-foreground"}`} />
                  Natural
                </button>
                <button
                  onClick={() => { if (!sortReversed) onToggleSortReversed(); setSortOpen(false); }}
                  disabled={sortMode === "manual"}
                  className="hover:bg-accent flex w-full items-center gap-2 px-3 py-1.5 text-left text-sm disabled:opacity-40 disabled:hover:bg-transparent"
                >
                  <ArrowUp className={`h-3.5 w-3.5 ${sortReversed ? "text-primary" : "text-muted-foreground"}`} />
                  Reversed
                </button>
              </div>
            )}
          </div>

          <button
            onClick={onToggleSearch}
            className={`rounded-md p-2.5 ${showSearch ? "text-foreground" : "text-muted-foreground hover:text-foreground"}`}
            title="Search"
          >
            <Search className="h-5 w-5" />
          </button>

          <button
            onClick={() => { lock(); void navigate({ to: "/login" }); }}
            className="text-muted-foreground hover:text-foreground rounded-md p-2.5"
            title="Lock Now"
          >
            <Lock className="h-5 w-5" />
          </button>
          <button
            onClick={async () => { await apiClient.logout(); lock(); logout(); void navigate({ to: "/login" }); }}
            className="text-muted-foreground hover:text-foreground rounded-md p-2.5"
            title="Sign Out"
          >
            <Shield className="h-5 w-5" />
          </button>
          <Link to="/settings" className="text-muted-foreground hover:text-foreground rounded-md p-2.5" title="Settings">
            <Settings className="h-5 w-5" />
          </Link>
          {onRequestShutdown && (
            <button
              onClick={onRequestShutdown}
              className="text-muted-foreground hover:text-destructive rounded-md p-2.5"
              title="Shut Down"
            >
              <Power className="h-5 w-5" />
            </button>
          )}
        </div>
      </header>

      {showSearch && (
        <div className="search-animate mb-4 flex items-center gap-2">
          <div className="border-input bg-background relative flex flex-1 items-center rounded-md border shadow-sm">
            <Search className="text-muted-foreground absolute left-3 h-4 w-4" />
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => onSearchChange(e.target.value)}
              placeholder="Search accounts..."
              className="bg-transparent w-full py-2 pl-9 pr-8 text-sm outline-none"
              autoFocus
            />
            {searchQuery && (
              <button
                onClick={() => onSearchChange("")}
                className="text-muted-foreground hover:text-foreground absolute right-2 p-0.5"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            )}
          </div>
        </div>
      )}
    </>
  );
}
