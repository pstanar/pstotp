# Security policy

## Reporting a vulnerability

**Do not** open a public GitHub issue for anything that would let an
attacker read vaults, impersonate users, escalate privilege, or bypass
authentication. Those reports should go through GitHub's private
security-advisories feature:

- On the repository page, click **Security → Advisories → Report a
  vulnerability**, or visit
  `https://github.com/<owner>/<repo>/security/advisories/new` once the
  repo is public.
- Fill in a description, reproduction steps or proof-of-concept, and
  an impact assessment as you see it.
- The maintainer will triage the report privately, discuss a fix in
  the same advisory thread, and publish the advisory + a patched
  release together when ready.

If you need to reach the maintainer before the repository is public —
or for something that isn't really a vulnerability but you'd rather
not post in the open (e.g. a suspected misconfiguration in a
deployment) — open a regular issue asking for a private channel and
the maintainer will reply with one.

Please include, to the extent you can:

- Affected version(s) (commit SHA or release tag).
- Deployment context (provider, reverse proxy, which client).
- A minimal reproduction or the smallest test case that shows the
  problem.
- Your own impact assessment, even if it's "I'm not sure how bad this
  is".

We don't run a paid bug-bounty programme. Credit in the advisory is
offered by default; tell us if you'd prefer to stay anonymous.

## Scope

PsTotp is designed as a **zero-knowledge** sync service: the server
stores and relays ciphertext, but is not trusted with plaintext vault
contents, raw passwords, or vault keys.

### What PsTotp is trying to protect

1. **Vault confidentiality against a curious or compromised server.**
   Vault entries (issuer, account name, TOTP secret, algorithm/digits/
   period) are encrypted client-side with a user-derived vault key.
   The server never sees any of these in plaintext, at rest or in
   transit.
2. **Password confidentiality against a curious or compromised server.**
   The raw password never leaves the client. Authentication uses a
   password-derived Argon2id verifier and a challenge-response proof;
   the server stores the verifier, not the password.
3. **Continued access after a device is lost.** The user can reach
   their vault from a second approved device, via password + device
   approval on a new device, via recovery codes, or via WebAuthn
   step-up recovery.
4. **Auditability of state-changing operations.** Every meaningful
   change (login success/failure, device approval/rejection/revocation,
   password change, recovery attempts, admin actions, backup
   export/restore) is recorded in an audit trail.
5. **Defence-in-depth for recovery.** Recovery codes authorise the
   flow; a hold period (24 hours by default) gives a legitimate owner
   time to notice a hostile recovery attempt and cancel it.

### What PsTotp is **not** trying to protect

- **A compromised client device.** Malware with root / equivalent
  access on a signed-in device can read the decrypted vault in memory.
  We reduce the attack surface (Android Keystore-backed biometric key
  wrapping, `FLAG_SECURE` on the activity, sensitive-clipboard
  metadata on Android, short-lived access tokens) but a fully
  compromised device is out of scope.
- **Network attackers defeating TLS.** Transport security is the
  transport layer's problem. Deploy behind a reverse proxy with a
  real certificate.
- **Supply-chain / tampered binaries.** The threat model assumes the
  running server binary and client builds are authentic. Code-signing
  on the client side is tracked but not yet in place for the Android
  release (see `memory/future_work.md`).
- **Side-channel analysis.** We use constant-time comparisons for
  password verifier and recovery-code hash checks (via provider
  primitives), but we don't claim resistance to active side-channel
  attacks against the server host itself.
- **Catastrophic credential + code loss.** If a user loses every
  approved device **and** their recovery codes, their vault is
  unrecoverable. This is by design — any "admin recovery" escape
  hatch would also be a zero-knowledge violation.

## Threat model summary

The full threat model lives in `docs/architecture/threat-model.md`.
Short version of who we trust for what:

| Party | Trusted for | Not trusted for |
| --- | --- | --- |
| Server | Policy (auth, admin), ciphertext storage, audit | Plaintext vault contents, raw passwords, vault keys |
| Client device | Rendering/using plaintext after unlock | Nothing while locked |
| Reverse proxy | TLS termination, request forwarding, trusted `X-Forwarded-*` headers | Application authorisation |
| Admin | Running the service, restoring backups, managing user accounts | Reading user vault contents — admin gets ciphertext only |
| Recovery code holder | Authorising the recovery flow | Immediate release of vault material (24h hold by default) |

## Cryptographic primitives

Pinned across clients and server. Changing these requires a design
conversation (see `docs/ADMIN.md` → *Crypto parameters*).

| Primitive | Use |
| --- | --- |
| **Argon2id** — `m=64 MB, t=3, p=4` | Password → authKey derivation (for verifier and envelope unwrap). Parameters are stamped per-user into `PasswordKdfConfig` at registration and preserved through logins. |
| **HKDF-SHA-256** | Key derivation with explicit per-purpose context strings (e.g. `vault-password-envelope-v1`). Separates authKey from envelope-wrap keys and verifier keys so one leak doesn't implicate the others. |
| **AES-256-GCM** | Authenticated encryption for vault entries, vault-key envelopes, and backup files. Vault entries use the entry ID as associated data so a server can't swap ciphertexts between entries undetected. |
| **HMAC-SHA-256** | Password proof over the server-issued login nonce + session ID. |
| **ECDH P-256** | Per-device key pair used to wrap vault keys into device-specific envelopes; public key is the device identity. |
| **WebAuthn / FIDO2** | Passkey registration and passwordless login. Attestation `none`, `residentKey=preferred`, `userVerification=preferred`. |

All crypto payloads include explicit version fields so we can rotate
primitives per-payload if we ever need to.

All binary values are carried over the wire as standard base64
(`Convert.ToBase64String` on the server, matching encoders on the
clients). Not base64url.

## Data locations and encryption at rest

| Location | Contents | Encrypted? |
| --- | --- | --- |
| Server DB — `vault_entries.entry_payload` | Issuer, account name, secret, algorithm, digits, period | Yes (AES-256-GCM, entry ID as AD) |
| Server DB — `vault_key_envelopes.wrapped_key_payload` | Vault key wrapped for password / device / recovery paths | Yes (AES-256-GCM) |
| Server DB — `recovery_codes.code_hash` | Argon2id hashes of recovery codes | Hashed — not reversible |
| Server DB — `users.password_verifier` | Password verifier bytes | Hashed — not reversible |
| Server DB — `webauthn_credentials` | Public key + metadata | Not encrypted (public material) |
| Server DB — `audit_events` | Event type, user/device IDs, IP, user-agent, JSON payload | Not encrypted — plaintext operational metadata |
| Admin backup file | Everything above (as-is) | Yes — Argon2id-derived AES-256-GCM with an admin-chosen password |
| Android local DB (`Room/SQLite`) | Same ciphertext as the server, plus user preferences | Entries: yes (same AEAD); preferences: not encrypted |
| Android biometric material | Vault-key ciphertext, wrap IV, wrap ciphertext | Yes — key is in Android Keystore, biometric-bound |
| Web `IndexedDB` | Device ECDH private key for passkey flows | Stored as non-exportable `CryptoKey` via WebCrypto |

## Known limitations

These are the trade-offs we're making today. Each one is known and
considered acceptable for the current threat model; a few have open
design tickets in `memory/future_work.md`.

- **Rate limiter is in-memory.** Login (5 attempts / 15 min) and
  recovery (3 / hour) counters reset on server restart. A motivated
  attacker who can induce restarts can reset their counter.
- **No certificate pinning in the Android client.** TLS validation
  uses the system trust store. A device with a malicious root CA
  installed can MITM the connection. Pinning is on the roadmap but
  adds operational pain around cert rotation.
- **Clipboard auto-clear is best-effort.** Android/iOS/desktop
  clipboard behaviour varies by OS version and by which apps have
  clipboard-read permissions at the moment the code is copied. We
  mark clips as sensitive (API 33+) so they don't appear in previews
  and we clear after 30 seconds, but another app reading the
  clipboard inside that window is outside our control.
- **Supply-chain / tampered binaries.** A signed Android release
  build isn't in place yet (tracked in `memory/future_work.md`); in
  the meantime, users install from source or debug builds whose
  provenance they have to trust themselves. The server self-contained
  builds aren't signed either.
- **Admin delete is irreversible.** The admin UI's delete action hard-
  removes a user and all their data in a single transaction. The
  only recovery from a mistaken deletion is restoring an admin
  backup from before the action. The UI requires explicit
  confirmation.
- **Admin backup is ciphertext-only.** This is a feature, not a
  limitation, but worth stating: an admin restoring a backup cannot
  read users' vault entries. Users still need their own passwords /
  passkeys / recovery codes to unlock after restore.
- **Audit events are never auto-pruned.** The `SessionCleanupService`
  deliberately leaves audit events alone. If the table grows
  uncomfortably, operators have to prune at the DB layer.
- **SMTP only (no OAuth2 XOAUTH2 yet).** Outlook.com doesn't support
  basic SMTP auth, and Gmail requires app passwords. For those
  providers, users currently need to either get an app password or
  route through a transactional-email relay.
- **No machine-auth path for admin endpoints.** Admin APIs are
  reachable only via interactive login today; scheduled backups via
  `curl` aren't possible. Tracked in `memory/future_work.md`.
- **Recovery hold period is a blocking delay, not a notification.**
  The 24-hour hold gives a legitimate user time to notice a hostile
  attempt, but only if they check — we don't push an out-of-band
  alert. For deployments with configured SMTP, email notifications
  for high-risk events are a reasonable add; not implemented today.

## Out-of-band considerations

- **Server operators should treat admin backup files like database
  credentials.** The ciphertext is strong, but the whole server's
  worth of encrypted data + the password together reconstruct the
  database.
- **The `Admins` config array is the only way to grant admin.** Any
  admin escalation story starts with having write access to the
  server config — that's the trust boundary.
- **WebAuthn RP ID is baked into registered credentials.** Changing
  `Fido2:ServerDomain` invalidates every registered passkey for every
  user. Don't casually move the hostname.

## Deeper reading

For design rationale and the full threat model:

- `docs/architecture/threat-model.md` — explicit adversary model,
  trust boundaries, attacks in and out of scope.
- `docs/architecture/key-hierarchy.md` — how the vault key, password
  envelope, device envelopes, and recovery envelope relate.
- `docs/architecture/vault-record-contract.md` — exact byte layout of
  encrypted vault entries.
- `docs/architecture/PLAN.md` — overall design including crypto
  choices and phase-by-phase implementation notes.

(Those files are not part of the public repo — they live alongside it
as design artefacts. The security-relevant content is summarised above;
if you're auditing and want more depth than this file provides, ask on
the security-advisories channel.)
