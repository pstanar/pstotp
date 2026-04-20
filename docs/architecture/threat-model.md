# Threat Model

## Assets

| Asset | Location | Sensitivity |
|---|---|---|
| TOTP secrets (plaintext) | Client memory only, while unlocked | Critical — grants access to user's 2FA-protected accounts |
| VaultKey | Client memory only, while unlocked | Critical — decrypts all vault entries |
| Password | Client memory only, during auth | High — derives verifier and envelope key |
| Encrypted vault entries | Server DB, client IndexedDB | Medium — ciphertext without key is inert |
| Wrapped vault key envelopes | Server DB | Medium — ciphertext, requires device key or password to unwrap |
| Password verifier | Server DB | Medium — allows authentication impersonation if stolen, but cannot decrypt vault |
| Recovery codes | User's offline storage (printed) | High — authorize emergency recovery flow |
| Recovery Seed | User's offline storage | Critical — cryptographic input for vault recovery |
| Device private keys | Client keystore (Web Crypto / Android Keystore) | High — unwraps device-specific vault key envelope |
| Refresh tokens | Server DB | Medium — grants session continuity |

## Threat scenarios

### T1: Stolen password

**Attacker has:** the user's password (phishing, credential stuffing, keylogger).

**What they can do:**
- Authenticate to the server and derive the password verifier
- Derive the password envelope key and unwrap VaultKey via the password envelope
- If they also have access to an active session or can register a new device: full vault access

**What they cannot do (without device approval):**
- Complete new-device registration — requires approval from an existing trusted device
- Access the vault from a new device without the approval step

**Mitigations:**
- New-device approval requires an existing trusted device to authorize
- Password-only sessions on web are ephemeral (no persistent unwrap material)
- Audit logging of all login attempts and device registrations
- Rate limiting on login endpoints
- User notification on new device registration attempts

**Residual risk:** If the attacker also controls an approved device (see T2), password knowledge grants full access. Password change + device revocation is the response.

---

### T2: Stolen unlocked device

**Attacker has:** physical access to a device where the vault is currently unlocked in memory.

**What they can do:**
- Read all decrypted TOTP codes currently displayed
- Copy TOTP secrets from memory if they can attach a debugger
- Use the active session to sync, export, or modify vault entries
- Approve new devices from this trusted device

**What they cannot do:**
- Access the vault after the auto-lock timeout fires
- Access the vault after device reboot (keys cleared)
- Recover the vault key after the app is locked (memory cleared)

**Mitigations:**
- Auto-lock after short inactivity (web: 3–5 min, mobile: 30–60 sec background)
- Lock on device reboot and app restart
- Explicit "Lock now" action
- Android: `FLAG_SECURE` to prevent app-switcher preview of codes
- Step-up re-authentication required for sensitive actions (device approval, recovery, password change)
- Device revocation from another trusted device

**Residual risk:** Anything visible on screen at the moment of theft is compromised. Auto-lock limits the window.

---

### T3: Stolen encrypted server database

**Attacker has:** full copy of PostgreSQL database contents.

**What they get:**
- Encrypted vault entry blobs (`entry_payload`) — ciphertext only
- Wrapped vault key envelopes — ciphertext only
- Password verifiers (Argon2id hashes)
- Recovery code hashes
- Device metadata (names, platforms, timestamps)
- Audit event history
- WebAuthn credential public keys

**What they can do:**
- Attempt offline brute-force against password verifiers (Argon2id with m=64MB makes this expensive)
- Attempt to impersonate users if they crack a verifier (authentication only, still no vault key)
- Correlate device metadata and audit trails

**What they cannot do:**
- Decrypt any vault entries (VaultKey never stored on server)
- Derive VaultKey from password verifier (verifier and envelope key use different HKDF contexts)
- Use WebAuthn public keys to sign challenges (private keys are on devices)
- Use recovery code hashes to recover the vault (hashes are one-way; recovery also requires the Recovery Seed)

**Mitigations:**
- Argon2id with aggressive parameters (m=64MB, t=3, p=4) for password verifier
- Separate HKDF derivation paths for auth verifier vs. envelope key — cracking the verifier does not yield the envelope key
- All vault content encrypted client-side before upload
- Recovery codes stored as slow hashes only
- Database encryption at rest (PostgreSQL TDE or disk-level)
- Regular security patching and access controls on database host

**Residual risk:** Device metadata and audit trails are visible in plaintext. Issuer and account names are encrypted inside vault entry payloads, so no TOTP account metadata leaks.

---

### T4: Malicious email/account recovery attempt

**Attacker has:** access to the user's email inbox (compromised email account).

**What they can do:**
- Receive notification emails about device registrations and recovery attempts
- Attempt to start account-level recovery

**What they cannot do:**
- Decrypt the vault — email is never sufficient to release vault recovery material
- Complete recovery — requires a valid recovery code (offline artifact) plus password, optionally YubiKey
- Bypass the recovery hold period (24–48 hours) — user receives notifications and can cancel
- Approve a new device — requires an existing approved device, not email

**Mitigations:**
- Email is a notification channel only, never an authorization factor for vault access
- Recovery hold period with cancellation window
- Recovery requires: recovery code + password + optional WebAuthn step-up
- All recovery attempts are audited and notified to all known devices
- Rate limiting on recovery endpoints

**Residual risk:** Attacker with email access can observe notifications and learn when the user is active. They cannot act on vault contents.

---

### T5: Replay or tampering during sync

**Attacker has:** ability to intercept or modify network traffic (MITM position).

**What they can do (without TLS bypass):**
- Nothing — all API traffic is HTTPS

**What they can do (with TLS bypass, e.g., compromised CA):**
- Replay captured API requests
- Modify encrypted payloads in transit
- Intercept JWT tokens and impersonate sessions
- Attempt to downgrade or swap vault entries

**Mitigations:**
- HTTPS required for all API communication
- AEAD encryption on vault entries — tampered ciphertext fails authentication tag verification on the client
- Optimistic concurrency via `entryVersion` — stale or replayed writes are rejected by the server
- Short-lived JWT access tokens with refresh token rotation
- Refresh token rotation: previous token revoked on each refresh, limiting replay window
- Challenge-response login flow with server-issued nonce — replay of `clientProof` fails because nonce is single-use
- HSTS headers to prevent protocol downgrade

**Residual risk:** A full MITM with TLS bypass could deny service or delay sync but cannot decrypt vault contents (client-side encryption). Session hijacking via stolen JWT is time-bounded by token expiry.

## Summary matrix

| Threat | Vault secrets exposed? | Requires additional factor? | Primary defense |
|---|---|---|---|
| T1: Stolen password | No (without device approval) | Device approval | Multi-factor device bootstrap |
| T2: Stolen unlocked device | Yes (while unlocked) | Physical access | Auto-lock, step-up auth |
| T3: Stolen server DB | No | N/A | Client-side encryption, separated key derivation |
| T4: Malicious recovery | No | Recovery code + password | Email is notification-only |
| T5: Replay/tampering | No | TLS bypass | HTTPS, AEAD, nonce-based challenge |
