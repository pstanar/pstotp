import { useState } from "react";
import { useAuthStore } from "@/stores/useAuthStore";
import { useVaultStore } from "@/stores/useVaultStore";
import { ApiError } from "@/lib/api-client";
import { validatePassword } from "@/lib/password-validation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  derivePasswordAuthKey,
  derivePasswordVerifier,
  derivePasswordEnvelopeKey,
  deriveRecoveryUnlockKey,
  computeClientProof,
  aesGcmEncrypt,
  generateSalt,
  toBase64,
  fromBase64,
} from "@/lib/crypto";
import {
  requestLoginChallenge,
  changePassword,
} from "@/features/auth/api/auth-api";
import { regenerateRecoveryCodes } from "@/features/recovery/api/recovery-api";
import { getDeviceInfoWithKeyPair } from "@/features/auth/utils/device-info";
import type { KdfConfig } from "@/types/api-types";

type Status = "idle" | "verifying" | "deriving-old" | "deriving-new" | "submitting" | "success";

export function ChangePasswordForm() {
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<Status>("idle");
  const email = useAuthStore((s) => s.email);
  const vaultKey = useVaultStore((s) => s.vaultKey);

  const loading = status !== "idle" && status !== "success";

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (newPassword !== confirmPassword) {
      setError("Passwords do not match.");
      return;
    }
    const validation = validatePassword(newPassword);
    if (!validation.valid) {
      setError("Password requirements: " + validation.errors.join(", "));
      return;
    }
    if (!email || !vaultKey) {
      setError("Not authenticated.");
      return;
    }

    try {
      // Step 1: Get login challenge for step-up proof
      setStatus("verifying");
      const { device } = await getDeviceInfoWithKeyPair();
      const challenge = await requestLoginChallenge(email, device);

      // Step 2: Derive OLD password verifier and compute proof
      setStatus("deriving-old");
      const oldSalt = fromBase64(challenge.challenge.kdf.salt);
      const oldAuthKey = await derivePasswordAuthKey(currentPassword, oldSalt, challenge.challenge.kdf);
      const oldVerifier = await derivePasswordVerifier(oldAuthKey);
      const nonce = fromBase64(challenge.challenge.nonce);
      const proof = await computeClientProof(oldVerifier, nonce, challenge.loginSessionId);

      // Step 3: Derive NEW password verifier + envelope key
      setStatus("deriving-new");
      const newSalt = generateSalt();
      const newKdfConfig: KdfConfig = {
        algorithm: "argon2id",
        memoryMb: 64,
        iterations: 3,
        parallelism: 4,
        salt: toBase64(newSalt),
      };
      const newAuthKey = await derivePasswordAuthKey(newPassword, newSalt, newKdfConfig);
      const newVerifier = await derivePasswordVerifier(newAuthKey);
      const newEnvelopeKey = await derivePasswordEnvelopeKey(newAuthKey);

      // Step 4: Wrap VaultKey with new envelope key
      const { ciphertext, nonce: envNonce } = await aesGcmEncrypt(newEnvelopeKey, vaultKey);

      // Step 5: Call password change endpoint
      setStatus("submitting");
      await changePassword(
        { loginSessionId: challenge.loginSessionId, clientProof: toBase64(proof) },
        { verifier: toBase64(newVerifier), kdf: newKdfConfig },
        { ciphertext: toBase64(ciphertext), nonce: toBase64(envNonce), version: 1 },
      );

      // Password changed — now rotate recovery envelope (best-effort).
      // If this fails, password is still changed but recovery needs manual code regeneration.
      let envelopeWarning = "";
      try {
        const newRecoveryUnlockKey = await deriveRecoveryUnlockKey(newAuthKey);
        const newRecoveryEnvelope = await aesGcmEncrypt(newRecoveryUnlockKey, vaultKey);
        await regenerateRecoveryCodes({
          recoveryEnvelopeCiphertext: toBase64(newRecoveryEnvelope.ciphertext),
          recoveryEnvelopeNonce: toBase64(newRecoveryEnvelope.nonce),
          recoveryEnvelopeVersion: 1,
          recoveryCodeHashes: [],
        });
      } catch {
        envelopeWarning = "Password changed, but recovery envelope could not be updated. Please regenerate your recovery codes.";
      }

      setStatus("success");
      if (envelopeWarning) setError(envelopeWarning);
      setCurrentPassword("");
      setNewPassword("");
      setConfirmPassword("");
    } catch (err) {
      setStatus("idle");
      if (err instanceof ApiError) {
        if (err.status === 401) setError("Current password is incorrect.");
        else if (err.status === 403) setError("Device not approved for this operation.");
        else if (err.status === 429) setError("Too many attempts. Please try again later.");
        else setError(err.message);
      } else {
        setError(err instanceof Error ? err.message : "Password change failed.");
      }
    }
  };

  if (status === "success") {
    return (
      <div className="space-y-2">
        <p className="text-sm font-medium text-emerald-600 dark:text-emerald-400">Password changed successfully.</p>
        {error && <p className="text-sm text-amber-600 dark:text-amber-400">{error}</p>}
        <Button variant="link" size="sm" onClick={() => { setStatus("idle"); setError(null); }} className="h-auto p-0">
          Change again
        </Button>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-3">
      <input type="email" value={email ?? ""} autoComplete="username" readOnly hidden aria-hidden="true" tabIndex={-1} />
      <Input id="current-password" type="password" required label="Current Password"
        value={currentPassword} onChange={(e) => setCurrentPassword(e.target.value)}
        disabled={loading} autoComplete="current-password" />
      <Input id="new-password" type="password" required label="New Password"
        value={newPassword} onChange={(e) => setNewPassword(e.target.value)}
        disabled={loading} autoComplete="new-password" />
      <Input id="confirm-password" type="password" required label="Confirm New Password"
        value={confirmPassword} onChange={(e) => setConfirmPassword(e.target.value)}
        disabled={loading} autoComplete="new-password" />

      {error && <p className="text-destructive text-sm">{error}</p>}

      <Button type="submit" disabled={loading} size="sm">
        {loading
          ? status === "verifying" ? "Verifying..."
          : status === "deriving-old" ? "Verifying current password..."
          : status === "deriving-new" ? "Deriving new keys..."
          : "Changing password..."
          : "Change Password"}
      </Button>
    </form>
  );
}
