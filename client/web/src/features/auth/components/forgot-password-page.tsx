import { useState } from "react";
import { Link, useNavigate } from "@tanstack/react-router";
import { ArrowLeft } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useAuthStore } from "@/stores/useAuthStore";
import { useVaultStore } from "@/stores/useVaultStore";
import { ApiError } from "@/lib/api-client";
import { validatePassword } from "@/lib/password-validation";
import {
  derivePasswordAuthKey,
  derivePasswordVerifier,
  derivePasswordEnvelopeKey,
  aesGcmEncrypt,
  generateSalt,
  toBase64,
} from "@/lib/crypto";
import {
  beginPasswordReset,
  verifyPasswordResetCode,
  completePasswordReset,
} from "@/features/auth/api/auth-api";
import { getDeviceInfoWithKeyPair } from "@/features/auth/utils/device-info";
import { saveDeviceKeyPair } from "@/lib/device-key-store";
import {
  fetchAndDecryptVault,
  rebuildDeviceEnvelope,
} from "@/features/auth/utils/vault-unlock";
import type { Envelope, KdfConfig } from "@/types/api-types";

type Step = "email" | "code" | "new-password" | "processing" | "no-device-key" | "done";

export function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [step, setStep] = useState<Step>("email");
  const [resetSessionId, setResetSessionId] = useState<string | null>(null);
  const [devCode, setDevCode] = useState<string | null>(null);
  const [vaultKey, setVaultKeyLocal] = useState<Uint8Array | null>(null);

  const loginStore = useAuthStore((s) => s.login);
  const setVaultKey = useVaultStore((s) => s.setVaultKey);
  const unlock = useVaultStore((s) => s.unlock);
  const navigate = useNavigate();

  const handleBegin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    try {
      const { device } = await getDeviceInfoWithKeyPair();
      const result = await beginPasswordReset(email, device);
      setResetSessionId(result.resetSessionId);
      if (result.verificationCode) setDevCode(result.verificationCode);
      setStep("code");
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Failed to start password reset.");
    }
  };

  const handleVerifyCode = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (!resetSessionId) return;

    try {
      const result = await verifyPasswordResetCode(resetSessionId, code);
      if (!result.verified) {
        setError("Invalid verification code.");
        return;
      }

      // Try to decrypt vault key via device envelope
      if (result.deviceEnvelope) {
        const key = await tryDecryptDeviceEnvelopeByKey(result.deviceEnvelope);
        if (key) {
          setVaultKeyLocal(key);
          setStep("new-password");
          return;
        }
      }

      // No device key available
      setStep("no-device-key");
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Verification failed.");
    }
  };

  const handleSetNewPassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (!resetSessionId || !vaultKey) return;

    const validation = validatePassword(newPassword);
    if (!validation.valid) {
      setError(validation.errors[0]);
      return;
    }
    if (newPassword !== confirmPassword) {
      setError("Passwords do not match.");
      return;
    }

    try {
      setStep("processing");

      // Derive new password key material
      const salt = generateSalt();
      const newKdf: KdfConfig = {
        algorithm: "argon2id", memoryMb: 64, iterations: 3, parallelism: 4,
        salt: toBase64(salt),
      };
      const authKey = await derivePasswordAuthKey(newPassword, salt, newKdf);
      const verifier = await derivePasswordVerifier(authKey);
      const envelopeKey = await derivePasswordEnvelopeKey(authKey);
      const envelope = await aesGcmEncrypt(envelopeKey, vaultKey);

      const result = await completePasswordReset(
        resetSessionId,
        { verifier: toBase64(verifier), kdf: newKdf },
        { ciphertext: toBase64(envelope.ciphertext), nonce: toBase64(envelope.nonce), version: 1 },
      );

      if (!result.device) {
        setError("Password reset completed but no device info returned.");
        setStep("new-password");
        return;
      }

      // Log in
      loginStore({
        userId: result.userId,
        email,
        deviceId: result.device.deviceId,
        deviceStatus: result.device.status,
        role: result.role ?? null,
      });
      const { keyPair } = await getDeviceInfoWithKeyPair();
      await saveDeviceKeyPair(result.device.deviceId, keyPair);

      // Unlock vault
      setVaultKey(vaultKey);
      const entries = await fetchAndDecryptVault(vaultKey);
      unlock(entries);

      // Rebuild device envelope with new key material
      rebuildDeviceEnvelope(vaultKey, keyPair.publicKey);

      void navigate({ to: "/" });
    } catch (err) {
      setStep("new-password");
      setError(err instanceof ApiError ? err.message : "Failed to reset password.");
    }
  };

  return (
    <div className="mx-auto max-w-sm px-4 py-12">
      <div className="mb-6 flex items-center gap-3">
        <Link to="/login" className="text-muted-foreground hover:text-foreground">
          <ArrowLeft className="h-5 w-5" />
        </Link>
        <h1 className="text-xl font-bold">Forgot Password</h1>
      </div>

      {step === "email" && (
        <form onSubmit={handleBegin} className="space-y-4">
          <p className="text-muted-foreground text-sm">
            Enter your email address. We'll send a verification code to reset your password.
          </p>
          <Input id="reset-email" type="email" required label="Email" value={email}
            onChange={(e) => setEmail(e.target.value)} placeholder="alice@example.com"
            autoComplete="email" autoFocus />
          {error && <p className="text-destructive text-sm">{error}</p>}
          <Button type="submit" className="w-full">Send Code</Button>
        </form>
      )}

      {step === "code" && (
        <form onSubmit={handleVerifyCode} className="space-y-4">
          <p className="text-muted-foreground text-sm">
            Enter the verification code sent to {email}.
          </p>
          {devCode && (
            <div className="bg-accent rounded-md px-3 py-2 text-xs">
              Dev mode — code: <span className="font-mono font-bold">{devCode}</span>
            </div>
          )}
          <Input id="reset-code" type="text" required label="Verification Code" value={code}
            onChange={(e) => setCode(e.target.value)} className="font-mono"
            autoComplete="one-time-code" autoFocus />
          {error && <p className="text-destructive text-sm">{error}</p>}
          <Button type="submit" className="w-full">Verify</Button>
        </form>
      )}

      {step === "new-password" && (
        <form onSubmit={handleSetNewPassword} className="space-y-4">
          <div className="rounded-md border border-green-500/30 bg-green-500/10 px-4 py-2 text-sm text-green-700 dark:text-green-400">
            Identity verified. Set your new password.
          </div>
          <input type="email" value={email} autoComplete="username" readOnly hidden aria-hidden="true" tabIndex={-1} />
          <Input id="new-password" type="password" required label="New Password" value={newPassword}
            onChange={(e) => setNewPassword(e.target.value)} autoComplete="new-password" autoFocus />
          <Input id="confirm-password" type="password" required label="Confirm Password" value={confirmPassword}
            onChange={(e) => setConfirmPassword(e.target.value)} autoComplete="new-password" />
          {error && <p className="text-destructive text-sm">{error}</p>}
          <Button type="submit" className="w-full">Reset Password</Button>
        </form>
      )}

      {step === "processing" && (
        <p className="text-muted-foreground text-center text-sm">Resetting password...</p>
      )}

      {step === "no-device-key" && (
        <div className="space-y-4">
          <div className="rounded-md border border-amber-500/30 bg-amber-500/10 px-4 py-3 text-sm text-amber-700 dark:text-amber-400">
            This browser doesn't have your device key. Password reset requires the same browser you previously logged in from.
          </div>
          <p className="text-muted-foreground text-sm">
            If you have recovery codes, you can use account recovery instead.
          </p>
          <Link to="/recovery">
            <Button variant="secondary" className="w-full">Go to Account Recovery</Button>
          </Link>
          <Link to="/login">
            <Button variant="ghost" className="w-full">Back to Login</Button>
          </Link>
        </div>
      )}
    </div>
  );
}

/** Try to decrypt device envelope using the local ECDH key pair from IndexedDB. */
async function tryDecryptDeviceEnvelopeByKey(envelope: Envelope): Promise<Uint8Array | null> {
  const { unpackEcdhDeviceEnvelope } = await import("@/lib/crypto");
  const { getOrCreateLocalKeyPair } = await import("@/lib/device-key-store");
  const { generateEcdhKeyPair } = await import("@/lib/crypto");

  const keyPair = await getOrCreateLocalKeyPair(generateEcdhKeyPair);
  try {
    return await unpackEcdhDeviceEnvelope(envelope.ciphertext, envelope.nonce, keyPair.privateKey);
  } catch {
    return null;
  }
}
