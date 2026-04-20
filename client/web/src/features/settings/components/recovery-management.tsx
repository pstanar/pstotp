import { useState } from "react";
import { useAuthStore } from "@/stores/useAuthStore";
import { useVaultStore } from "@/stores/useVaultStore";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import {
  derivePasswordAuthKey,
  derivePasswordVerifier,
  computeClientProof,
  generateSalt,
  generateRecoveryCode,
  hashRecoveryCode,
  deriveRecoveryUnlockKey,
  aesGcmEncrypt,
  toBase64,
  fromBase64,
} from "@/lib/crypto";
import { requestLoginChallenge, completeLogin } from "@/features/auth/api/auth-api";
import { regenerateRecoveryCodes } from "@/features/recovery/api/recovery-api";
import { getDeviceInfoWithKeyPair } from "@/features/auth/utils/device-info";

export function RecoveryManagement() {
  const vaultKey = useVaultStore((s) => s.vaultKey);
  const email = useAuthStore((s) => s.email);
  const [status, setStatus] = useState<"idle" | "confirm" | "generating" | "done" | "error">("idle");
  const [password, setPassword] = useState("");
  const [codes, setCodes] = useState<string[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleRegenerate = async () => {
    if (!vaultKey || !email) {
      setError("Vault key or email not available");
      return;
    }
    if (!password) {
      setError("Password is required");
      return;
    }

    setStatus("generating");
    setError(null);

    try {
      // Get KDF config from server via login challenge
      const { device } = await getDeviceInfoWithKeyPair();
      const challenge = await requestLoginChallenge(email, device);
      const salt = fromBase64(challenge.challenge.kdf.salt);

      // Derive authKey and verify password via login proof
      const authKey = await derivePasswordAuthKey(password, salt, challenge.challenge.kdf);
      const verifier = await derivePasswordVerifier(authKey);
      const nonce = fromBase64(challenge.challenge.nonce);
      const proof = await computeClientProof(verifier, nonce, challenge.loginSessionId);
      await completeLogin(challenge.loginSessionId, toBase64(proof));

      // Generate new codes with a dedicated salt (independent of password KDF salt)
      const recoveryCodeSalt = generateSalt();
      const newCodes = Array.from({ length: 8 }, () => generateRecoveryCode());
      const codeHashes: string[] = [];
      for (const code of newCodes) {
        codeHashes.push(await hashRecoveryCode(code, recoveryCodeSalt));
      }

      // Encrypt recovery envelope with password-derived key
      const recoveryUnlockKey = await deriveRecoveryUnlockKey(authKey);
      const newRecoveryEnvelope = await aesGcmEncrypt(recoveryUnlockKey, vaultKey);

      await regenerateRecoveryCodes({
        recoveryEnvelopeCiphertext: toBase64(newRecoveryEnvelope.ciphertext),
        recoveryEnvelopeNonce: toBase64(newRecoveryEnvelope.nonce),
        recoveryEnvelopeVersion: 1,
        recoveryCodeHashes: codeHashes,
        recoveryCodeSalt: toBase64(recoveryCodeSalt),
      });

      setCodes(newCodes);
      setPassword("");
      setStatus("done");
    } catch {
      setError("Failed to regenerate recovery codes. Check your password.");
      setStatus("confirm");
    }
  };

  return (
    <div>
      <label className="text-sm font-medium">Recovery Codes</label>
      <p className="text-muted-foreground mt-0.5 mb-3 text-sm">
        Recovery codes let you regain access if you lose all your devices.
      </p>

      {status === "idle" && (
        <button
          onClick={() => setStatus("confirm")}
          className="rounded-md bg-amber-600 px-4 py-2 text-sm font-medium text-white hover:bg-amber-700 transition-colors"
        >
          Regenerate Recovery Codes
        </button>
      )}

      {status === "confirm" && (
        <div className="rounded-md border border-amber-500/30 bg-amber-500/10 p-4 space-y-3">
          <p className="text-sm font-medium text-amber-700 dark:text-amber-400">
            This will invalidate all existing recovery codes. Enter your password to continue.
          </p>
          <Input
            id="recovery-password"
            type="password"
            label="Password"
            value={password}
            onChange={(e) => { setPassword(e.target.value); setError(null); }}
            autoComplete="current-password"
          />
          {error && <p className="text-sm text-destructive">{error}</p>}
          <div className="flex gap-2">
            <Button
              onClick={handleRegenerate}
              disabled={!password}
              className="bg-amber-600 hover:bg-amber-700"
            >
              Regenerate
            </Button>
            <Button
              variant="secondary"
              onClick={() => { setStatus("idle"); setPassword(""); setError(null); }}
            >
              Cancel
            </Button>
          </div>
        </div>
      )}

      {status === "generating" && (
        <p className="text-sm text-muted-foreground">Generating new recovery codes...</p>
      )}

      {status === "done" && codes && (
        <div className="space-y-3">
          <div className="rounded-md border border-green-500/30 bg-green-500/10 p-4">
            <p className="text-sm font-medium text-green-700 dark:text-green-400 mb-2">
              New recovery codes generated. Save them in a safe place.
            </p>
            <div className="grid grid-cols-1 gap-1.5 font-mono text-sm sm:grid-cols-2 sm:text-base">
              {codes.map((code, i) => (
                <div key={i} className="rounded bg-background/60 px-2 py-1 text-center">
                  {code}
                </div>
              ))}
            </div>
          </div>
          <button
            onClick={() => { setCodes(null); setStatus("idle"); }}
            className="rounded-md border border-border px-4 py-2 text-sm font-medium hover:bg-muted transition-colors"
          >
            Done
          </button>
        </div>
      )}
    </div>
  );
}
