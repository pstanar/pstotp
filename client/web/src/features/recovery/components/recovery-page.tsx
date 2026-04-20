import { useState } from "react";
import { Link, useNavigate } from "@tanstack/react-router";
import { ArrowLeft } from "lucide-react";
import { ApiError } from "@/lib/api-client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useAuthStore } from "@/stores/useAuthStore";
import { useVaultStore } from "@/stores/useVaultStore";
import {
  derivePasswordAuthKey,
  derivePasswordVerifier,
  computeClientProof,
  deriveRecoveryUnlockKey,
  aesGcmDecrypt,
  aesGcmEncrypt,
  packEcdhDeviceEnvelope,
  generateSalt,
  generateRecoveryCode,
  hashRecoveryCode,
  toBase64,
  fromBase64,
} from "@/lib/crypto";
import { startAuthentication } from "@simplewebauthn/browser";
import { requestLoginChallenge } from "@/features/auth/api/auth-api";
import { redeemRecoveryCode, getRecoveryMaterial, completeRecovery } from "@/features/recovery/api/recovery-api";
import { beginAssertion, completeAssertion } from "@/features/webauthn/api/webauthn-api";
import { getDeviceInfoWithKeyPair } from "@/features/auth/utils/device-info";
import { saveDeviceKeyPair } from "@/lib/device-key-store";
import { fetchVault } from "@/features/vault/api/vault-api";
import { decryptEntry } from "@/features/vault/utils/vault-crypto";

type Step = "input" | "processing" | "webauthn" | "pending" | "completing" | "done";

export function RecoveryPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [recoveryCode, setRecoveryCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [step, setStep] = useState<Step>("input");
  const [releaseTime, setReleaseTime] = useState<string | null>(null);
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [savedAuthKey, setSavedAuthKey] = useState<Uint8Array | null>(null);
  const [savedKeyPair, setSavedKeyPair] = useState<CryptoKeyPair | null>(null);
  const [newRecoveryCodes, setNewRecoveryCodes] = useState<string[] | null>(null);
  const [copied, setCopied] = useState(false);

  const loginStore = useAuthStore((s) => s.login);
  const setVaultKey = useVaultStore((s) => s.setVaultKey);
  const unlock = useVaultStore((s) => s.unlock);
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    try {
      setStep("processing");

      // Step 1: Get login challenge for step-up proof
      const { device, keyPair } = await getDeviceInfoWithKeyPair();
      const challenge = await requestLoginChallenge(email, device);
      const salt = fromBase64(challenge.challenge.kdf.salt);
      const authKey = await derivePasswordAuthKey(password, salt, challenge.challenge.kdf);
      const verifier = await derivePasswordVerifier(authKey);
      const nonce = fromBase64(challenge.challenge.nonce);
      const proof = await computeClientProof(verifier, nonce, challenge.loginSessionId);

      // Step 2: Redeem recovery code
      const redeemResult = await redeemRecoveryCode(email, recoveryCode, {
        loginSessionId: challenge.loginSessionId,
        clientProof: toBase64(proof),
      });

      setSessionId(redeemResult.recoverySessionId);

      // Step 3: Request material
      let material = await getRecoveryMaterial(redeemResult.recoverySessionId, device);

      // WebAuthn step-up if required
      if (material.status === "webauthn_required") {
        setStep("webauthn");
        const { ceremonyId, publicKeyOptions } = await beginAssertion(undefined, redeemResult.recoverySessionId);
        const assertionResp = await startAuthentication({ optionsJSON: publicKeyOptions });
        await completeAssertion(ceremonyId, assertionResp);
        // Retry material after WebAuthn completion
        material = await getRecoveryMaterial(redeemResult.recoverySessionId, device);
      }

      if (material.status === "pending") {
        setSavedAuthKey(authKey);
        setSavedKeyPair(keyPair);
        setReleaseTime(material.releaseEarliestAt ?? null);
        setStep("pending");
        return;
      }

      // Step 4: Material is ready — decrypt recovery envelope
      if (!material.recoveryEnvelope || !material.replacementDeviceId) {
        setError("Recovery material incomplete.");
        setStep("input");
        return;
      }

      setStep("completing");
      await finishRecovery(authKey, keyPair, material.recoveryEnvelope, material.replacementDeviceId);
    } catch (err) {
      setStep("input");
      if (err instanceof ApiError) {
        if (err.status === 401) setError("Invalid email or password.");
        else if (err.status === 429) setError("Too many attempts. Please try again later.");
        else setError(err.message);
      } else {
        setError(err instanceof Error ? err.message : "Recovery failed.");
      }
    }
  };

  const finishRecovery = async (
    authKey: Uint8Array, keyPair: CryptoKeyPair,
    envelope: { ciphertext: string; nonce: string }, replacementDeviceId: string,
  ) => {
    const recoveryNonce = fromBase64(envelope.nonce);
    const recoveryCiphertext = fromBase64(envelope.ciphertext);
    const recoveryUnlockKey = await deriveRecoveryUnlockKey(authKey);
    const vaultKey = await aesGcmDecrypt(recoveryUnlockKey, recoveryCiphertext, recoveryNonce);

    const recoveryCodeSalt = generateSalt();
    const codes = Array.from({ length: 8 }, () => generateRecoveryCode());
    const codeHashes: string[] = [];
    for (const code of codes) {
      codeHashes.push(await hashRecoveryCode(code, recoveryCodeSalt));
    }

    const devEnvelope = await packEcdhDeviceEnvelope(vaultKey, keyPair.publicKey);
    const newRecoveryUnlockKey = await deriveRecoveryUnlockKey(authKey);
    const newRecoveryEnvelope = await aesGcmEncrypt(newRecoveryUnlockKey, vaultKey);

    const completeResult = await completeRecovery(
      sessionId!, replacementDeviceId,
      { ciphertext: devEnvelope.ciphertext, nonce: devEnvelope.nonce, version: 1 },
      {
        recoveryEnvelopeCiphertext: toBase64(newRecoveryEnvelope.ciphertext),
        recoveryEnvelopeNonce: toBase64(newRecoveryEnvelope.nonce),
        recoveryEnvelopeVersion: 1,
        recoveryCodeHashes: codeHashes,
        recoveryCodeSalt: toBase64(recoveryCodeSalt),
      },
    );

    loginStore({
      userId: completeResult.userId, email, deviceId: replacementDeviceId,
      deviceStatus: "approved", role: null,
    });
    await saveDeviceKeyPair(replacementDeviceId, keyPair);
    setVaultKey(vaultKey);

    const vaultResponse = await fetchVault();
    const entries = await Promise.all(
      vaultResponse.entries.filter((dto) => !dto.deletedAt).map(async (dto) => {
        const pt = await decryptEntry(vaultKey, dto.entryPayload, dto.id);
        return { ...pt, id: dto.id, version: dto.entryVersion };
      }),
    );
    unlock(entries);

    setNewRecoveryCodes(codes);
    setStep("done");
  };

  const handleRetryMaterial = async () => {
    if (!sessionId || !savedAuthKey || !savedKeyPair) return;
    setError(null);
    try {
      const { device } = await getDeviceInfoWithKeyPair();
      const material = await getRecoveryMaterial(sessionId, device);
      if (material.status === "ready") {
        if (!material.recoveryEnvelope || !material.replacementDeviceId) {
          setError("Recovery material is incomplete. If this persists, the session expires in 72 hours — you can start a new recovery after that.");
          return;
        }
        setStep("completing");
        await finishRecovery(savedAuthKey, savedKeyPair, material.recoveryEnvelope, material.replacementDeviceId);
      } else if (material.status === "pending") {
        setReleaseTime(material.releaseEarliestAt ?? null);
      } else {
        setError(`Unexpected recovery status: ${material.status}`);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to check status.");
    }
  };

  // Recovery codes display after completion
  if (step === "done" && newRecoveryCodes) {
    return (
      <div className="mx-auto max-w-sm px-4 py-12">
        <div className="space-y-6">
          <div className="text-center">
            <h1 className="text-2xl font-bold">Account Recovered</h1>
            <p className="text-muted-foreground mt-2 text-sm">
              Save your new recovery codes. The old codes are no longer valid.
            </p>
          </div>

          <div className="bg-muted rounded-lg p-4 font-mono text-sm sm:text-base">
            <div className="grid grid-cols-1 gap-1.5 sm:grid-cols-2 sm:gap-2">
              {newRecoveryCodes.map((code, i) => (
                <div key={i} className="text-center">{code}</div>
              ))}
            </div>
          </div>

          <Button variant="secondary" className="w-full"
            onClick={async () => {
              await navigator.clipboard.writeText(newRecoveryCodes.join("\n"));
              setCopied(true);
              setTimeout(() => setCopied(false), 2000);
            }}>
            {copied ? "Copied!" : "Copy to clipboard"}
          </Button>

          <p className="text-destructive text-center text-xs font-medium">
            These codes will not be shown again.
          </p>

          <Button className="w-full" onClick={() => void navigate({ to: "/" })}>
            Go to Vault
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-sm px-4 py-12">
      <div className="mb-6 flex items-center gap-3">
        <Link to="/login" className="text-muted-foreground hover:text-foreground">
          <ArrowLeft className="h-5 w-5" />
        </Link>
        <h1 className="text-xl font-bold">Account Recovery</h1>
      </div>

      {step === "pending" && (
        <div className="space-y-4">
          <div className="bg-accent rounded-lg p-4 text-center">
            <p className="text-sm font-medium">Recovery Hold Period</p>
            <p className="text-muted-foreground mt-1 text-sm">
              For security, recovery material will be available after:
            </p>
            <p className="mt-2 font-mono text-sm font-bold">
              {releaseTime ? new Date(releaseTime).toLocaleString() : "Unknown"}
            </p>
          </div>
          <Button className="w-full" onClick={() => void handleRetryMaterial()}>
            Check Again
          </Button>
          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>
      )}

      {(step === "input" || step === "processing" || step === "webauthn" || step === "completing") && (
        <form onSubmit={handleSubmit} className="space-y-4">
          <p className="text-muted-foreground text-sm">
            Enter your email, password, and one of your recovery codes to regain access.
          </p>

          <Input id="recovery-email" type="email" required label="Email" value={email}
            onChange={(e) => setEmail(e.target.value)} disabled={step !== "input"}
            placeholder="alice@example.com" autoComplete="email" />
          <Input id="recovery-password" type="password" required label="Password" value={password}
            onChange={(e) => setPassword(e.target.value)} disabled={step !== "input"} autoComplete="current-password" />
          <Input id="recovery-code" type="text" required label="Recovery Code" value={recoveryCode}
            onChange={(e) => setRecoveryCode(e.target.value)} disabled={step !== "input"}
            className="font-mono" placeholder="ABCD1234XY" />

          {error && <p className="text-destructive text-sm">{error}</p>}

          <Button type="submit" disabled={step !== "input"} className="w-full">
            {step === "processing" ? "Verifying..." : step === "webauthn" ? "Verify passkey..." : step === "completing" ? "Recovering..." : "Recover Account"}
          </Button>
        </form>
      )}
    </div>
  );
}
