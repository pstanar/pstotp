import { apiClient } from "@/lib/api-client";
import type {
  RecoveryRedeemResponse,
  RecoveryMaterialResponse,
  DeviceDto,
  Envelope,
  RecoveryDto,
} from "@/types/api-types";

export function redeemRecoveryCode(
  email: string,
  recoveryCode: string,
  verifierProof: { loginSessionId: string; clientProof: string },
): Promise<RecoveryRedeemResponse> {
  return apiClient.post<RecoveryRedeemResponse>("/recovery/codes/redeem", {
    email,
    recoveryCode,
    verifierProof,
  });
}

export function getRecoveryMaterial(
  sessionId: string,
  replacementDevice: DeviceDto,
): Promise<RecoveryMaterialResponse> {
  return apiClient.post<RecoveryMaterialResponse>(
    `/recovery/session/${sessionId}/material`,
    { replacementDevice },
  );
}

export function completeRecovery(
  sessionId: string,
  replacementDeviceId: string,
  deviceEnvelope: Envelope,
  rotatedRecovery: RecoveryDto,
): Promise<{ userId: string }> {
  return apiClient.post<{ userId: string }>(`/recovery/session/${sessionId}/complete`, {
    replacementDeviceId,
    deviceEnvelope,
    rotatedRecovery,
  });
}

export function regenerateRecoveryCodes(
  rotatedRecovery: RecoveryDto,
): Promise<{ rotatedAt: string }> {
  return apiClient.post<{ rotatedAt: string }>("/recovery/codes/regenerate", {
    rotatedRecovery,
  });
}

export function cancelRecoverySession(sessionId: string): Promise<void> {
  return apiClient.post<void>(`/recovery/session/${sessionId}/cancel`, {});
}
