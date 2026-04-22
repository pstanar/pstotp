import { apiClient } from "@/lib/api-client";

export interface IconLibraryResponse {
  encryptedPayload: string; // base64; empty string when no library exists yet
  version: number;          // server's monotonic version; 0 means no library
  updatedAt: string | null;
}

export interface IconLibraryUpdateRequest {
  encryptedPayload: string;
  expectedVersion: number;
}

export interface IconLibraryUpdateResponse {
  version: number;
  updatedAt: string;
}

export function fetchIconLibrary(): Promise<IconLibraryResponse> {
  return apiClient.get<IconLibraryResponse>("/vault/icon-library");
}

export function putIconLibrary(
  encryptedPayload: string,
  expectedVersion: number,
): Promise<IconLibraryUpdateResponse> {
  return apiClient.put<IconLibraryUpdateResponse>(
    "/vault/icon-library",
    { encryptedPayload, expectedVersion },
  );
}
