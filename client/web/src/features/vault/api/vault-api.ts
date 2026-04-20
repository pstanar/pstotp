import { apiClient } from "@/lib/api-client";
import type { VaultSyncResponse } from "@/types/api-types";

export function fetchVault(): Promise<VaultSyncResponse> {
  return apiClient.get<VaultSyncResponse>("/vault");
}

export interface VaultUpsertResponse {
  id: string;
  entryVersion: number;
  updatedAt: string;
}

export function upsertEntry(
  entryId: string,
  entryPayload: string,
  entryVersion: number,
): Promise<VaultUpsertResponse> {
  return apiClient.put<VaultUpsertResponse>(`/vault/${entryId}`, {
    entryPayload,
    entryVersion,
  });
}

export function deleteEntry(entryId: string): Promise<void> {
  return apiClient.delete<void>(`/vault/${entryId}`);
}

export function reorderEntries(entryIds: string[]): Promise<void> {
  return apiClient.post<void>("/vault/reorder", { entryIds });
}
