import { useState } from "react";
import { useNavigate } from "@tanstack/react-router";
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
  aesGcmEncrypt,
  generateSalt,
  generateVaultKey,
  generateRecoveryCode,
  hashRecoveryCode,
  deriveRecoveryUnlockKey,
  packEcdhDeviceEnvelope,
  toBase64,
} from "@/lib/crypto";
import { register, registerBegin, verifyEmail } from "@/features/auth/api/auth-api";
import { getDeviceInfoWithKeyPair } from "@/features/auth/utils/device-info";
import { saveDeviceKeyPair } from "@/lib/device-key-store";
import type { KdfConfig } from "@/types/api-types";

interface RegisterFormProps {
  onSwitchToLogin: () => void;
}

type Status = "idle" | "verifying-email" | "deriving-keys" | "registering" | "hashing-recovery" | "done";

export function RegisterForm({ onSwitchToLogin }: RegisterFormProps) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<Status>("idle");
  const [recoveryCodes, setRecoveryCodes] = useState<string[] | null>(null);
  const [copied, setCopied] = useState(false);

  // Email verification state
  const [verificationSessionId, setVerificationSessionId] = useState<string | null>(null);
  const [verificationCode, setVerificationCode] = useState("");
  const [devVerificationCode, setDevVerificationCode] = useState<string | null>(null);

  const login = useAuthStore((s) => s.login);
  const setVaultKey = useVaultStore((s) => s.setVaultKey);
  const unlock = useVaultStore((s) => s.unlock);
  const navigate = useNavigate();

  const loading = status !== "idle" && status !== "done";

  const statusText: Record<Status, string> = {
    idle: "",
    "verifying-email": "Verifying email...",
    "deriving-keys": "Deriving encryption keys...",
    registering: "Creating account...",
    "hashing-recovery": "Generating recovery codes...",
    done: "",
  };

  const handleRegister = async (sessionId?: string) => {
    const { device, keyPair } = await getDeviceInfoWithKeyPair();
    const salt = generateSalt();
    const vaultKey = generateVaultKey();

    setStatus("deriving-keys");
    const kdfConfig: KdfConfig = {
      algorithm: "argon2id", memoryMb: 64, iterations: 3, parallelism: 4,
      salt: toBase64(salt),
    };
    const passwordAuthKey = await derivePasswordAuthKey(password, salt, kdfConfig);
    const verifier = await derivePasswordVerifier(passwordAuthKey);
    const envelopeKey = await derivePasswordEnvelopeKey(passwordAuthKey);

    setStatus("registering");
    const pwEnvelope = await aesGcmEncrypt(envelopeKey, vaultKey);
    const devEnvelope = await packEcdhDeviceEnvelope(vaultKey, keyPair.publicKey);
    // Recovery envelope encrypted with password-derived key so recovery
    // can decrypt using the same password (proven via step-up auth)
    const recoveryUnlockKey = await deriveRecoveryUnlockKey(passwordAuthKey);
    const recEnvelope = await aesGcmEncrypt(recoveryUnlockKey, vaultKey);

    setStatus("hashing-recovery");
    const recoveryCodeSalt = generateSalt();
    const codes = Array.from({ length: 8 }, () => generateRecoveryCode());
    const codeHashes: string[] = [];
    for (const code of codes) {
      codeHashes.push(await hashRecoveryCode(code, recoveryCodeSalt));
    }

    setStatus("registering");
    const result = await register({
      registrationSessionId: sessionId ?? null,
      email,
      passwordVerifier: { verifier: toBase64(verifier), kdf: kdfConfig },
      passwordEnvelope: { ciphertext: toBase64(pwEnvelope.ciphertext), nonce: toBase64(pwEnvelope.nonce), version: 1 },
      device,
      deviceEnvelope: { ciphertext: devEnvelope.ciphertext, nonce: devEnvelope.nonce, version: 1 },
      recovery: {
        recoveryEnvelopeCiphertext: toBase64(recEnvelope.ciphertext),
        recoveryEnvelopeNonce: toBase64(recEnvelope.nonce),
        recoveryEnvelopeVersion: 1,
        recoveryCodeHashes: codeHashes,
        recoveryCodeSalt: toBase64(recoveryCodeSalt),
      },
    });

    login({ userId: result.userId, email, deviceId: result.deviceId, deviceStatus: "approved", role: null });
    await saveDeviceKeyPair(result.deviceId, keyPair);
    setVaultKey(vaultKey);
    unlock([]);
    return codes;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    const validation = validatePassword(password);
    if (!validation.valid) {
      setError("Password requirements: " + validation.errors.join(", "));
      return;
    }

    try {
      if (!verificationSessionId) {
        // Step 1: Begin registration with email verification
        setStatus("verifying-email");
        const result = await registerBegin(email);
        setVerificationSessionId(result.registrationSessionId);
        if (result.verificationCode) setDevVerificationCode(result.verificationCode);
        setStatus("idle");
      } else {
        // Step 2: Verify code and complete registration
        setStatus("verifying-email");
        await verifyEmail(verificationSessionId, verificationCode);
        const codes = await handleRegister(verificationSessionId);
        setStatus("done");
        setRecoveryCodes(codes);
      }
    } catch (err) {
      setStatus("idle");
      if (err instanceof ApiError) {
        if (err.status === 409) setError("Email already registered.");
        else if (err.status === 429) setError("Too many attempts. Please try again later.");
        else setError(err.message);
      } else {
        setError(err instanceof Error ? err.message : "Registration failed");
      }
    }
  };

  // Recovery codes display
  if (recoveryCodes) {
    return (
      <div className="space-y-6">
        <div className="text-center">
          <h2 className="text-2xl font-bold">Recovery Codes</h2>
          <p className="text-muted-foreground mt-2 text-sm">
            Save these codes in a safe place. They are the only way to recover
            your account if you lose access to all your devices.
          </p>
        </div>

        <div className="bg-muted rounded-lg p-4 font-mono text-sm sm:text-base">
          <div className="grid grid-cols-1 gap-1.5 sm:grid-cols-2 sm:gap-2">
            {recoveryCodes.map((code, i) => (
              <div key={i} className="text-center">{code}</div>
            ))}
          </div>
        </div>

        <Button variant="secondary" className="w-full"
          onClick={async () => {
            await navigator.clipboard.writeText(recoveryCodes.join("\n"));
            setCopied(true);
            setTimeout(() => setCopied(false), 2000);
          }}>
          {copied ? "Copied!" : "Copy to clipboard"}
        </Button>

        <p className="text-destructive text-center text-xs font-medium">
          These codes will not be shown again.
        </p>

        <Button className="w-full"
          onClick={() => { setRecoveryCodes(null); void navigate({ to: "/" }); }}>
          I've saved my recovery codes
        </Button>
      </div>
    );
  }

  return (
    <>
      <form onSubmit={handleSubmit} className="space-y-4">
        <Input id="reg-email" type="email" required label="Email" value={email}
          onChange={(e) => setEmail(e.target.value)} disabled={loading}
          placeholder="alice@example.com" autoComplete="email" />
        <Input id="reg-password" type="password" required label="Password" value={password}
          onChange={(e) => setPassword(e.target.value)} disabled={loading} autoComplete="new-password" />

        {verificationSessionId && (
          <div>
            {devVerificationCode && (
              <div className="bg-accent mb-2 rounded-md px-3 py-2 text-xs">
                Dev mode — verification code: <span className="font-mono font-bold">{devVerificationCode}</span>
              </div>
            )}
            <Input id="verification-code" type="text" required label="Verification Code"
              value={verificationCode}
              onChange={(e) => setVerificationCode(e.target.value)} disabled={loading}
              className="font-mono" placeholder="123456" autoFocus />
            <p className="text-muted-foreground mt-1 text-xs">Check your email for the 6-digit code.</p>
          </div>
        )}

        {error && <p className="text-destructive text-sm">{error}</p>}

        <Button type="submit" disabled={loading} className="w-full">
          {loading ? statusText[status] : (verificationSessionId ? "Verify & Create Account" : "Create Account")}
        </Button>
      </form>

      <p className="text-muted-foreground text-center text-sm">
        Already have an account?{" "}
        <Button variant="link" size="sm" onClick={onSwitchToLogin} disabled={loading}
          className="h-auto p-0">Sign in</Button>
      </p>
    </>
  );
}
