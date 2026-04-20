import { apiClient } from "@/lib/api-client";
import type { DeviceInfo, Envelope } from "@/types/api-types";

export interface DeviceListResponse {
  devices: DeviceInfo[];
}

export function fetchDevices(): Promise<DeviceListResponse> {
  return apiClient.get<DeviceListResponse>("/devices");
}

export function approveDevice(
  deviceId: string,
  approvalRequestId: string,
  deviceEnvelope: Envelope,
): Promise<void> {
  return apiClient.post<void>(`/devices/${deviceId}/approve`, {
    approvalRequestId,
    approvalAuth: { type: "device" },
    deviceEnvelope,
  });
}

export function rejectDevice(deviceId: string): Promise<void> {
  return apiClient.post<void>(`/devices/${deviceId}/reject`);
}

export function revokeDevice(deviceId: string): Promise<void> {
  return apiClient.post<void>(`/devices/${deviceId}/revoke`);
}

export function updateSelfEnvelope(envelope: Envelope): Promise<void> {
  return apiClient.put<void>("/devices/self/envelope", envelope);
}
