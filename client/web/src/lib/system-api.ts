import { apiClient } from "@/lib/api-client";

export interface SystemInfo {
  shutdownAvailable: boolean;
  multiUser: boolean;
}

export function getSystemInfo(): Promise<SystemInfo> {
  return apiClient.get<SystemInfo>("/system/info");
}

export function shutdownServer(): Promise<void> {
  return apiClient.post("/system/shutdown");
}
