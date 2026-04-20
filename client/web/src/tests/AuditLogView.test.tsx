import { describe, it, expect } from "vitest";

// Inline the formatting functions from audit-panel (they're not exported)
function formatEventType(type: string): string {
  return type
    .replace(/_/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

function formatEventDetail(event: {
  eventData?: string;
  ipAddress?: string;
}): string {
  const parts: string[] = [];
  if (event.eventData) {
    try {
      const data = JSON.parse(event.eventData) as Record<string, unknown>;
      if (data.DeviceName) parts.push(String(data.DeviceName));
      if (data.Email) parts.push(String(data.Email));
      if (data.ApprovedBy) parts.push(`approved by ${String(data.ApprovedBy)}`);
    } catch { /* ignore */ }
  }
  if (event.ipAddress) parts.push(`IP: ${event.ipAddress}`);
  return parts.join(" · ");
}

describe("AuditLogView", () => {
  it("formats event types in human-readable form", () => {
    expect(formatEventType("login_success")).toBe("Login Success");
    expect(formatEventType("account_created")).toBe("Account Created");
    expect(formatEventType("device_approved")).toBe("Device Approved");
    expect(formatEventType("login_failed")).toBe("Login Failed");
    expect(formatEventType("device_revoked")).toBe("Device Revoked");
  });

  it("formats event detail with device name and IP", () => {
    const detail = formatEventDetail({
      eventData: JSON.stringify({ DeviceName: "Chrome on Windows" }),
      ipAddress: "192.168.1.5",
    });
    expect(detail).toBe("Chrome on Windows · IP: 192.168.1.5");
  });

  it("formats event detail with email", () => {
    const detail = formatEventDetail({
      eventData: JSON.stringify({ Email: "alice@example.com", DeviceName: "Firefox on macOS" }),
    });
    expect(detail).toBe("Firefox on macOS · alice@example.com");
  });

  it("formats approval with approved-by", () => {
    const detail = formatEventDetail({
      eventData: JSON.stringify({
        DeviceName: "Edge on Windows",
        ApprovedBy: "Chrome on Windows",
      }),
      ipAddress: "10.0.0.1",
    });
    expect(detail).toBe("Edge on Windows · approved by Chrome on Windows · IP: 10.0.0.1");
  });

  it("shows only IP when no event data", () => {
    const detail = formatEventDetail({ ipAddress: "1.2.3.4" });
    expect(detail).toBe("IP: 1.2.3.4");
  });

  it("returns empty string when no data", () => {
    const detail = formatEventDetail({});
    expect(detail).toBe("");
  });

  it("handles malformed event data gracefully", () => {
    const detail = formatEventDetail({
      eventData: "not json",
      ipAddress: "5.6.7.8",
    });
    expect(detail).toBe("IP: 5.6.7.8");
  });
});
