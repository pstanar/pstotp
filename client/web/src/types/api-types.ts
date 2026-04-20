export interface KdfConfig {
  algorithm: string;
  memoryMb: number;
  iterations: number;
  parallelism: number;
  salt: string;
}

export interface Envelope {
  ciphertext: string;
  nonce: string;
  version: number;
}

export interface LoginChallengeResponse {
  loginSessionId: string;
  challenge: {
    nonce: string;
    kdf: KdfConfig;
  };
}

export interface LoginCompleteResponse {
  userId: string;
  accessToken: string | null;
  refreshToken: string | null;
  device: {
    deviceId: string;
    status: string;
    persistentKeyAllowed: boolean;
  };
  envelopes?: {
    password?: Envelope;
    device?: Envelope;
  };
  approvalRequestId?: string;
  role?: string;
  forcePasswordReset?: boolean;
}

export interface RegisterResponse {
  userId: string;
  deviceId: string;
  accessToken: string | null;
  refreshToken: string | null;
}

export interface BeginRegistrationResponse {
  registrationSessionId: string;
  emailVerificationRequired: boolean;
  verificationCode?: string; // Only in dev mode
}

export interface PasswordChangeResponse {
  accessToken: string;
  refreshToken: string;
}

export interface RecoveryRedeemResponse {
  recoverySessionId: string;
  requiresWebAuthn: boolean;
  releaseEarliestAt: string;
}

export interface RecoveryMaterialResponse {
  status: string;
  recoveryEnvelope?: Envelope;
  replacementDeviceId?: string;
  releaseEarliestAt?: string;
}

// --- Request DTOs ---

export interface PasswordVerifierDto {
  verifier: string;
  kdf: KdfConfig;
}

export interface DeviceDto {
  deviceName: string;
  platform: string;
  clientType: string;
  devicePublicKey: string;
}

export interface RecoveryDto {
  recoveryEnvelopeCiphertext: string;
  recoveryEnvelopeNonce: string;
  recoveryEnvelopeVersion: number;
  recoveryCodeHashes: string[];
  recoveryCodeSalt?: string;
}

export interface RegisterRequest {
  registrationSessionId?: string | null;
  email: string;
  passwordVerifier: PasswordVerifierDto;
  passwordEnvelope: Envelope;
  device: DeviceDto;
  deviceEnvelope: Envelope;
  recovery: RecoveryDto;
}

// --- WebAuthn ---

export interface WebAuthnCredentialInfo {
  id: string;
  friendlyName: string | null;
  createdAt: string;
  lastUsedAt: string | null;
}

// --- Vault ---

export interface VaultEntryDto {
  id: string;
  entryPayload: string;
  entryVersion: number;
  deletedAt: string | null;
  updatedAt: string;
}

export interface VaultSyncResponse {
  entries: VaultEntryDto[];
  serverTime: string;
}

export interface DeviceInfo {
  deviceId: string;
  deviceName: string;
  platform: string;
  status: string;
  approvedAt?: string;
  approvalRequestId?: string;
  devicePublicKey?: string;
  requestedAt?: string;
  revokedAt?: string;
}

export interface AuditEvent {
  id: string;
  eventType: string;
  eventData?: string;
  ipAddress?: string;
  createdAt: string;
  deviceId?: string;
}
