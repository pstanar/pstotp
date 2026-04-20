import { apiClient } from "@/lib/api-client";
import type { AuditEvent } from "@/types/api-types";

export interface AuditEventsResponse {
  events: AuditEvent[];
}

export function fetchAuditEvents(limit: number = 200): Promise<AuditEventsResponse> {
  return apiClient.get<AuditEventsResponse>(`/security/audit-events?limit=${limit}`);
}
