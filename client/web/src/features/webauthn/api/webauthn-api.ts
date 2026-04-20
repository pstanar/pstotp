import type {
  PublicKeyCredentialCreationOptionsJSON,
  PublicKeyCredentialRequestOptionsJSON,
  RegistrationResponseJSON,
  AuthenticationResponseJSON,
} from "@simplewebauthn/browser";
import { apiClient } from "@/lib/api-client";
import type { WebAuthnCredentialInfo, Envelope } from "@/types/api-types";

// Registration (authenticated)
export function beginRegistration(): Promise<{
  ceremonyId: string;
  publicKeyOptions: PublicKeyCredentialCreationOptionsJSON;
}> {
  return apiClient.post("/webauthn/register/begin");
}

export function completeRegistration(
  ceremonyId: string,
  friendlyName: string,
  attestationResponse: RegistrationResponseJSON,
): Promise<{ id: string; friendlyName: string }> {
  return apiClient.post("/webauthn/register/complete", {
    ceremonyId,
    friendlyName,
    attestationResponse,
  });
}

// Assertion (public — login or recovery step-up)
export function beginAssertion(
  email?: string,
  recoverySessionId?: string,
): Promise<{
  ceremonyId: string;
  publicKeyOptions: PublicKeyCredentialRequestOptionsJSON;
}> {
  return apiClient.post("/webauthn/assert/begin", { email, recoverySessionId });
}

export function completeAssertion(
  ceremonyId: string,
  assertionResponse: AuthenticationResponseJSON,
  device?: { deviceName: string; platform: string; clientType: string; devicePublicKey: string },
): Promise<{
  success?: boolean;
  userId?: string;
  accessToken?: string | null;
  refreshToken?: string | null;
  device?: { deviceId: string; status: string; persistentKeyAllowed: boolean };
  envelopes?: { password?: Envelope; device?: Envelope };
  approvalRequestId?: string;
  role?: string;
  forcePasswordReset?: boolean;
}> {
  return apiClient.post("/webauthn/assert/complete", {
    ceremonyId,
    assertionResponse,
    device,
  });
}

// Management (authenticated)
export function listCredentials(): Promise<{ credentials: WebAuthnCredentialInfo[] }> {
  return apiClient.get("/webauthn/credentials");
}

export function renameCredential(credentialId: string, friendlyName: string): Promise<void> {
  return apiClient.put(`/webauthn/credentials/${credentialId}/rename`, { friendlyName });
}

export function revokeCredential(credentialId: string): Promise<void> {
  return apiClient.post(`/webauthn/credentials/${credentialId}/revoke`);
}
