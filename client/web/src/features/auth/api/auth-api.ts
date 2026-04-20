import { apiClient } from "@/lib/api-client";
import type {
  LoginChallengeResponse,
  LoginCompleteResponse,
  RegisterRequest,
  RegisterResponse,
  BeginRegistrationResponse,
  PasswordChangeResponse,
  DeviceDto,
  Envelope,
  KdfConfig,
  PasswordVerifierDto,
} from "@/types/api-types";

export function requestLoginChallenge(
  email: string,
  device: DeviceDto,
): Promise<LoginChallengeResponse> {
  return apiClient.post<LoginChallengeResponse>("/auth/login", {
    email,
    device,
  });
}

export function completeLogin(
  loginSessionId: string,
  clientProof: string,
): Promise<LoginCompleteResponse> {
  return apiClient.post<LoginCompleteResponse>("/auth/login/complete", {
    loginSessionId,
    clientProof,
  });
}

export function registerBegin(
  email: string,
): Promise<BeginRegistrationResponse> {
  return apiClient.post<BeginRegistrationResponse>("/auth/register/begin", { email });
}

export function verifyEmail(
  registrationSessionId: string,
  verificationCode: string,
): Promise<{ verified: boolean }> {
  return apiClient.post<{ verified: boolean }>("/auth/register/verify-email", {
    registrationSessionId,
    verificationCode,
  });
}

export function register(
  request: RegisterRequest,
): Promise<RegisterResponse> {
  return apiClient.post<RegisterResponse>("/auth/register", request);
}

// --- Password Reset ---

export function beginPasswordReset(
  email: string,
  device?: DeviceDto,
): Promise<{ resetSessionId: string; codeSent: boolean; verificationCode?: string }> {
  return apiClient.post("/auth/password/reset/begin", { email, device });
}

export function verifyPasswordResetCode(
  resetSessionId: string,
  verificationCode: string,
): Promise<{ verified: boolean; kdf?: KdfConfig; deviceEnvelope?: Envelope }> {
  return apiClient.post("/auth/password/reset/verify", { resetSessionId, verificationCode });
}

export function completePasswordReset(
  resetSessionId: string,
  newVerifier: PasswordVerifierDto,
  newPasswordEnvelope: Envelope,
): Promise<LoginCompleteResponse> {
  return apiClient.post("/auth/password/reset/complete", { resetSessionId, newVerifier, newPasswordEnvelope });
}

// --- Password Change ---

export function changePassword(
  currentProof: { loginSessionId: string; clientProof: string },
  newVerifier: PasswordVerifierDto,
  newPasswordEnvelope: Envelope,
): Promise<PasswordChangeResponse> {
  return apiClient.post<PasswordChangeResponse>("/account/password/change", {
    currentProof,
    newVerifier,
    newPasswordEnvelope,
  });
}
