import { useState, useEffect, useCallback, useMemo } from "react";
import { RefreshCw, Search, X, Download, ChevronLeft, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { fetchAuditEvents } from "@/features/audit/api/audit-api";
import type { AuditEvent } from "@/types/api-types";

const EVENT_TYPES = [
  { value: "", label: "All Events" },
  { value: "login_success", label: "Login Success" },
  { value: "login_failed", label: "Login Failed" },
  { value: "account_created", label: "Account Created" },
  { value: "device_approved", label: "Device Approved" },
  { value: "device_rejected", label: "Device Rejected" },
  { value: "device_revoked", label: "Device Revoked" },
];

const DATE_RANGES = [
  { value: "24h", label: "Last 24h" },
  { value: "7d", label: "Last 7 days" },
  { value: "30d", label: "Last 30 days" },
  { value: "all", label: "All time" },
];

const PAGE_SIZES = [10, 25, 50];

function getDateCutoff(range: string): Date | null {
  const now = new Date();
  switch (range) {
    case "24h": return new Date(now.getTime() - 24 * 60 * 60 * 1000);
    case "7d": return new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    case "30d": return new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    default: return null;
  }
}

export function AuditPanel() {
  const [events, setEvents] = useState<AuditEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Filters
  const [searchQuery, setSearchQuery] = useState("");
  const [eventTypeFilter, setEventTypeFilter] = useState("");
  const [dateRange, setDateRange] = useState("30d");

  // Pagination
  const [page, setPage] = useState(0);
  const [pageSize, setPageSize] = useState(25);

  const loadEvents = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const response = await fetchAuditEvents();
      setEvents(response.events);
    } catch {
      setError("Failed to load audit events.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadEvents();
  }, [loadEvents]);

  // Reset page when filters change
  useEffect(() => {
    setPage(0);
  }, [searchQuery, eventTypeFilter, dateRange, pageSize]);

  const filteredEvents = useMemo(() => {
    let result = events;

    // Event type filter
    if (eventTypeFilter) {
      result = result.filter((e) => e.eventType === eventTypeFilter);
    }

    // Date range filter
    const cutoff = getDateCutoff(dateRange);
    if (cutoff) {
      result = result.filter((e) => new Date(e.createdAt) >= cutoff);
    }

    // Search
    if (searchQuery) {
      const q = searchQuery.toLowerCase();
      result = result.filter((e) => {
        const detail = formatEventDetail(e).toLowerCase();
        const type = e.eventType.toLowerCase();
        return detail.includes(q) || type.includes(q);
      });
    }

    return result;
  }, [events, eventTypeFilter, dateRange, searchQuery]);

  const totalPages = Math.max(1, Math.ceil(filteredEvents.length / pageSize));
  const pagedEvents = filteredEvents.slice(page * pageSize, (page + 1) * pageSize);

  const handleExport = () => {
    const header = "Date,Event Type,Details,IP Address\n";
    const rows = filteredEvents.map((e) => {
      const date = new Date(e.createdAt).toISOString();
      const type = formatEventType(e.eventType);
      const detail = formatEventDetail(e).replace(/,/g, ";");
      const ip = e.ipAddress ?? "";
      return `${date},${type},${detail},${ip}`;
    });
    const csv = header + rows.join("\n");
    const blob = new Blob([csv], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `pstotp-audit-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div>
      {/* Header */}
      <div className="mb-4 flex items-center justify-between">
        <h2 className="text-sm font-semibold">Security Events</h2>
        <div className="flex items-center gap-1">
          <Button variant="ghost" size="icon"
            onClick={handleExport}
            disabled={filteredEvents.length === 0}
            title="Export CSV">
            <Download className="h-4 w-4" />
          </Button>
          <Button variant="ghost" size="icon"
            onClick={() => void loadEvents()}
            disabled={loading}
            title="Refresh">
            <RefreshCw className={`h-4 w-4 ${loading ? "animate-spin" : ""}`} />
          </Button>
        </div>
      </div>

      {/* Filters */}
      <div className="mb-4 space-y-2">
        {/* Search */}
        <div className="border-input bg-background relative flex items-center rounded-md border">
          <Search className="text-muted-foreground absolute left-3 h-4 w-4" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search events..."
            className="bg-transparent w-full py-2 pl-9 pr-8 text-sm outline-none"
          />
          {searchQuery && (
            <button
              onClick={() => setSearchQuery("")}
              className="text-muted-foreground hover:text-foreground absolute right-2 p-0.5"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          )}
        </div>

        {/* Type + Date range filters */}
        <div className="flex gap-2">
          <select
            value={eventTypeFilter}
            onChange={(e) => setEventTypeFilter(e.target.value)}
            className="border-input bg-background rounded-md border px-3 py-1.5 text-sm"
          >
            {EVENT_TYPES.map((t) => (
              <option key={t.value} value={t.value}>{t.label}</option>
            ))}
          </select>

          <div className="bg-muted flex rounded-md p-0.5">
            {DATE_RANGES.map((r) => (
              <button
                key={r.value}
                onClick={() => setDateRange(r.value)}
                className={`rounded px-2 py-1 text-xs font-medium ${
                  dateRange === r.value ? "bg-background shadow-sm" : "text-muted-foreground"
                }`}
              >
                {r.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      {error && (
        <div className="bg-destructive/10 text-destructive mb-4 rounded-md px-4 py-2 text-sm">
          {error}
        </div>
      )}

      {/* Event list */}
      {loading && events.length === 0 ? (
        <p className="text-muted-foreground text-center py-8">Loading events...</p>
      ) : filteredEvents.length === 0 ? (
        <p className="text-muted-foreground text-center py-8">
          {events.length === 0 ? "No audit events yet." : "No events match your filters."}
        </p>
      ) : (
        <>
          <div className="space-y-2">
            {pagedEvents.map((event) => (
              <div
                key={event.id}
                className="border-border flex items-center justify-between rounded-lg border px-4 py-3"
              >
                <div>
                  <p className="text-sm font-medium">{formatEventType(event.eventType)}</p>
                  <p className="text-muted-foreground text-xs">
                    {formatEventDetail(event)}
                  </p>
                </div>
                <p className="text-muted-foreground shrink-0 ml-4 text-xs">
                  {new Date(event.createdAt).toLocaleString()}
                </p>
              </div>
            ))}
          </div>

          {/* Pagination */}
          <div className="mt-4 flex items-center justify-between text-sm">
            <div className="flex items-center gap-2">
              <span className="text-muted-foreground text-xs">
                {filteredEvents.length} event{filteredEvents.length !== 1 ? "s" : ""}
              </span>
              <select
                value={pageSize}
                onChange={(e) => setPageSize(Number(e.target.value))}
                className="border-input bg-background rounded border px-2 py-1 text-xs"
              >
                {PAGE_SIZES.map((s) => (
                  <option key={s} value={s}>{s} per page</option>
                ))}
              </select>
            </div>

            <div className="flex items-center gap-1">
              <Button variant="ghost" size="icon"
                onClick={() => setPage((p) => Math.max(0, p - 1))}
                disabled={page === 0}>
                <ChevronLeft className="h-4 w-4" />
              </Button>
              <span className="text-muted-foreground text-xs px-2">
                {page + 1} / {totalPages}
              </span>
              <Button variant="ghost" size="icon"
                onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))}
                disabled={page >= totalPages - 1}>
                <ChevronRight className="h-4 w-4" />
              </Button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}

function formatEventType(type: string): string {
  return type
    .replace(/_/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

function formatEventDetail(event: AuditEvent): string {
  const parts: string[] = [];

  if (event.eventData) {
    try {
      const data = typeof event.eventData === "string"
        ? JSON.parse(event.eventData) as Record<string, unknown>
        : event.eventData as Record<string, unknown>;

      if (data.DeviceName) parts.push(String(data.DeviceName));
      if (data.Email) parts.push(String(data.Email));
      if (data.ApprovedBy) parts.push(`approved by ${String(data.ApprovedBy)}`);
    } catch {
      // ignore malformed data
    }
  }

  if (event.ipAddress) parts.push(`IP: ${event.ipAddress}`);

  return parts.join(" · ");
}
