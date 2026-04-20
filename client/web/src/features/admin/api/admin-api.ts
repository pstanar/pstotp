import { apiClient } from "@/lib/api-client";

export interface AdminUser {
  id: string;
  email: string;
  role: string;
  createdAt: string;
  lastLoginAt: string | null;
  disabledAt: string | null;
  forcePasswordReset: boolean;
  deviceCount: number;
  entryCount: number;
  credentialCount: number;
}

export interface AdminDevice {
  id: string;
  deviceName: string;
  platform: string;
  status: string;
  createdAt: string;
  approvedAt: string | null;
  revokedAt: string | null;
  lastSeenAt: string | null;
}

export function listUsers(search?: string): Promise<{ users: AdminUser[]; totalCount: number }> {
  const params = search ? `?search=${encodeURIComponent(search)}` : "";
  return apiClient.get(`/admin/users${params}`);
}

export function getUserDetail(userId: string): Promise<{ user: AdminUser; devices: AdminDevice[]; recoverySessions?: AdminRecoverySession[] }> {
  return apiClient.get(`/admin/users/${userId}`);
}

export function disableUser(userId: string): Promise<void> {
  return apiClient.post(`/admin/users/${userId}/disable`);
}

export function enableUser(userId: string): Promise<void> {
  return apiClient.post(`/admin/users/${userId}/enable`);
}

export function forcePasswordReset(userId: string): Promise<void> {
  return apiClient.post(`/admin/users/${userId}/force-password-reset`);
}

export function deleteUser(userId: string): Promise<void> {
  return apiClient.delete(`/admin/users/${userId}`);
}

export interface AdminRecoverySession {
  id: string;
  status: string;
  createdAt: string;
  expiresAt: string;
  releaseEarliestAt: string;
}

export function cancelRecoverySession(userId: string, sessionId: string): Promise<void> {
  return apiClient.post(`/admin/users/${userId}/recovery-sessions/${sessionId}/cancel`);
}
