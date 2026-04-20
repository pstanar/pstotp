import { useState } from "react";
import { Link, useNavigate } from "@tanstack/react-router";
import { startAuthentication } from "@simplewebauthn/browser";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useAuthStore } from "@/stores/useAuthStore";
import { useVaultStore } from "@/stores/useVaultStore";
import { ApiError } from "@/lib/api-client";
import {
  derivePasswordAuthKey,
  derivePasswordVerifier,
  derivePasswordEnvelopeKey,
  computeClientProof,
  toBase64,
  fromBase64,
} from "@/lib/crypto";
import { requestLoginChallenge, completeLogin } from "@/features/auth/api/auth-api";
import { beginAssertion, completeAssertion } from "@/features/webauthn/api/webauthn-api";
import { getDeviceInfoWithKeyPair } from "@/features/auth/utils/device-info";
import { saveDeviceKeyPair } from "@/lib/device-key-store";
import {
  fetchAndDecryptVault,
  tryDecryptDeviceEnvelope,
  decryptPasswordEnvelope,
  rebuildDeviceEnvelope,
} from "@/features/auth/utils/vault-unlock";
import type { Envelope } from "@/types/api-types";

interface LoginFormProps {
  onSwitchToRegister: () => void;
}

type Status = "idle" | "deriving-keys" | "authenticating" | "webauthn" | "need-password";

export function LoginForm({ onSwitchToRegister }: LoginFormProps) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<Status>("idle");
  const [passkeyEnvelopes, setPasskeyEnvelopes] = useState<{ password?: Envelope } | null>(null);
  const loginStore = useAuthStore((s) => s.login);
  const setVaultKey = useVaultStore((s) => s.setVaultKey);
  const unlock = useVaultStore((s) => s.unlock);
  const navigate = useNavigate();

  const loading = status !== "idle" && status !== "need-password";

  const statusText: Record<Status, string> = {
    idle: "",
    "deriving-keys": "Deriving encryption keys...",
    authenticating: "Authenticating...",
    webauthn: "Waiting for passkey...",
    "need-password": "",
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    try {
      setStatus("authenticating");
      const { device, keyPair } = await getDeviceInfoWithKeyPair();
      const challenge = await requestLoginChallenge(email, device);

      setStatus("deriving-keys");
      const salt = fromBase64(challenge.challenge.kdf.salt);
      const passwordAuthKey = await derivePasswordAuthKey(password, salt, challenge.challenge.kdf);
      const verifier = await derivePasswordVerifier(passwordAuthKey);

      setStatus("authenticating");
      const nonce = fromBase64(challenge.challenge.nonce);
      const proof = await computeClientProof(verifier, nonce, challenge.loginSessionId);
      const result = await completeLogin(challenge.loginSessionId, toBase64(proof));

      loginStore({
        userId: result.userId!,
        email,
        deviceId: result.device.deviceId,
        deviceStatus: result.device.status,
        role: result.role ?? null,
      });
      await saveDeviceKeyPair(result.device.deviceId, keyPair);

      let vaultKey: Uint8Array | null = null;
      let usedPasswordEnvelope = false;
      if (result.envelopes?.password) {
        const envelopeKey = await derivePasswordEnvelopeKey(passwordAuthKey);
        vaultKey = await decryptPasswordEnvelope(envelopeKey, result.envelopes.password);
        usedPasswordEnvelope = true;
      } else if (result.envelopes?.device) {
        vaultKey = await tryDecryptDeviceEnvelope(result.device.deviceId, result.envelopes.device);
      }

      if (vaultKey) {
        setVaultKey(vaultKey);
        const entries = await fetchAndDecryptVault(vaultKey);
        unlock(entries);
        if (usedPasswordEnvelope) {
          rebuildDeviceEnvelope(vaultKey, keyPair.publicKey);
        }
      }

      setStatus("idle");
      if (result.device.status === "pending") {
        setError("This device is pending approval from an existing device.");
      } else {
        void navigate({ to: "/" });
      }
    } catch (err) {
      setStatus("idle");
      if (err instanceof ApiError) {
        if (err.status === 401) setError("Invalid email or password.");
        else if (err.status === 429) setError("Too many attempts. Please try again later.");
        else setError(err.message);
      } else {
        setError(err instanceof Error ? err.message : "Authentication failed");
      }
    }
  };

  const handlePasskeyLogin = async () => {
    setError(null);
    try {
      setStatus("webauthn");
      const { device, keyPair } = await getDeviceInfoWithKeyPair();
      const { ceremonyId, publicKeyOptions } = await beginAssertion(email || undefined);
      const assertionResp = await startAuthentication({ optionsJSON: publicKeyOptions });
      const result = await completeAssertion(ceremonyId, assertionResp, device);

      if (!result.device) {
        setError("Passkey verified but no device info returned.");
        setStatus("idle");
        return;
      }

      loginStore({
        userId: result.userId!,
        email,
        deviceId: result.device.deviceId,
        deviceStatus: result.device.status,
        role: result.role ?? null,
      });
      await saveDeviceKeyPair(result.device.deviceId, keyPair);

      let vaultKey: Uint8Array | null = null;
      if (result.envelopes?.device) {
        vaultKey = await tryDecryptDeviceEnvelope(result.device.deviceId, result.envelopes.device);
      }

      if (vaultKey) {
        setVaultKey(vaultKey);
        const entries = await fetchAndDecryptVault(vaultKey);
        unlock(entries);
        setStatus("idle");
        void navigate({ to: "/" });
      } else if (result.device.status === "pending") {
        setStatus("idle");
        setError("This device is pending approval from an existing device.");
      } else if (result.envelopes?.password) {
        setPasskeyEnvelopes(result.envelopes);
        setStatus("need-password");
        setPassword("");
      } else {
        setStatus("idle");
        setError("Passkey verified but no envelope available to unlock vault.");
      }
    } catch (err) {
      setStatus("idle");
      if (err instanceof Error && err.name === "NotAllowedError") return;
      if (err instanceof ApiError) {
        setError(err.message);
      } else {
        const msg = err instanceof Error ? err.message : String(err);
        setError(`Passkey authentication failed: ${msg}`);
      }
    }
  };

  const handleUnlockAfterPasskey = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!passkeyEnvelopes?.password) return;
    setError(null);

    try {
      setStatus("deriving-keys");
      const { device, keyPair } = await getDeviceInfoWithKeyPair();
      const challenge = await requestLoginChallenge(email, device);
      const salt = fromBase64(challenge.challenge.kdf.salt);
      const authKey = await derivePasswordAuthKey(password, salt, challenge.challenge.kdf);
      const envelopeKey = await derivePasswordEnvelopeKey(authKey);
      const vaultKey = await decryptPasswordEnvelope(envelopeKey, passkeyEnvelopes.password);

      setVaultKey(vaultKey);
        const entries = await fetchAndDecryptVault(vaultKey);
        unlock(entries);
      rebuildDeviceEnvelope(vaultKey, keyPair.publicKey);

      setStatus("idle");
      setPasskeyEnvelopes(null);
      void navigate({ to: "/" });
    } catch (err) {
      setStatus("need-password");
      if (err instanceof Error && err.message.includes("decrypt")) {
        setError("Incorrect password.");
      } else {
        setError(err instanceof Error ? err.message : "Unlock failed. Please try again.");
      }
    }
  };

  if (status === "need-password") {
    return (
      <form onSubmit={handleUnlockAfterPasskey} className="space-y-4">
        <div className="rounded-md border border-green-500/30 bg-green-500/10 px-4 py-2 text-sm text-green-700 dark:text-green-400">
          Passkey verified. Enter your password to unlock the vault.
        </div>

        <input type="email" value={email} autoComplete="username" readOnly hidden aria-hidden="true" tabIndex={-1} />
        <Input id="unlock-password" type="password" required label="Password" value={password}
          onChange={(e) => setPassword(e.target.value)} autoFocus autoComplete="current-password" />

        {error && <p className="text-destructive text-sm">{error}</p>}

        <Button type="submit" className="w-full">Unlock Vault</Button>
        <Button type="button" variant="secondary" className="w-full"
          onClick={() => { setStatus("idle"); setPasskeyEnvelopes(null); }}>
          Back
        </Button>
      </form>
    );
  }

  return (
    <>
      <form onSubmit={handleSubmit} className="space-y-4">
        <Input id="email" type="email" required label="Email" value={email}
          onChange={(e) => setEmail(e.target.value)} disabled={loading}
          placeholder="alice@example.com" autoComplete="email" />
        <Input id="password" type="password" required label="Password" value={password}
          onChange={(e) => setPassword(e.target.value)} disabled={loading} autoComplete="current-password" />

        {error && <p className="text-destructive text-sm">{error}</p>}

        <Button type="submit" disabled={loading} className="w-full">
          {loading ? statusText[status] : "Sign In"}
        </Button>

        <div className="relative my-1">
          <div className="absolute inset-0 flex items-center">
            <div className="border-border w-full border-t" />
          </div>
          <div className="relative flex justify-center text-xs">
            <span className="bg-background text-muted-foreground px-2">or</span>
          </div>
        </div>

        <Button type="button" variant="secondary" disabled={loading} className="w-full"
          onClick={() => void handlePasskeyLogin()}>
          {status === "webauthn" ? "Waiting for passkey..." : "Sign in with passkey"}
        </Button>
      </form>

      <p className="text-muted-foreground text-center text-sm">
        Need an account?{" "}
        <Button variant="link" size="sm" onClick={onSwitchToRegister} disabled={loading}
          className="h-auto p-0">Register</Button>
      </p>
      <p className="text-muted-foreground text-center text-sm">
        <Link to="/forgot-password" className="text-primary text-sm underline">Forgot password?</Link>
        {" · "}
        <Link to="/recovery" className="text-primary text-sm underline">Recover account</Link>
      </p>
    </>
  );
}
