# TOTP Sync App Plan

## Overview
This plan defines a responsive web-first TOTP application with a React web client, an Android companion client, and a C# .NET 10 backend for encrypted multi-device sync. It focuses on client-side encryption, device approval, and layered recovery using recovery codes, a second approved device, and optional hardware security keys such as YubiKey.

## Resolved security decisions
- Email is a notification and account-contact channel only. It is not sufficient to release vault recovery material.
- The web client supports TOTP generation, but persistent browser device keys require WebAuthn-backed approval. Password-only browser sessions may unlock temporarily but must not persist unwrap material.
- The server is trusted for policy enforcement, audit logging, and ciphertext storage, but not for plaintext vault contents or plaintext-sensitive metadata such as issuer and account name.
- Metadata privacy is enabled from day one: `issuer` and `accountName` are encrypted in stored vault payloads.
- Password authentication uses a password-derived verifier flow. The client never sends the raw password to the server.

## Goals
1. Create a secure architecture for storing TOTP entries encrypted on the client before upload.
2. Implement a shared-vault model that supports one user across multiple approved devices.
3. Prioritize a responsive React web client that works well on desktop and mobile-sized screens, with Android following after the web foundation is stable.
4. Enable new-device bootstrap with both password knowledge and explicit device approval where possible.
5. Provide a survivable recovery path for the "last device lost" scenario using recovery codes and hardware-backed recovery options.
6. Add production-oriented protections such as audit logs, rate limiting, and abuse controls.

## Recovery decision matrix
| Recovery method | Security strength | User convenience | Best use | Main tradeoff |
| --- | --- | --- | --- | --- |
| Second approved device | High | High when another trusted device exists | Default bootstrap and recovery path | Fails if the user loses every approved device |
| Recovery codes | High if stored offline safely | Medium | Emergency last-device recovery | User must store codes securely and rotate after use |
| Hardware security key (YubiKey) | High | Medium | Step-up recovery and strong account re-verification | Requires extra hardware and WebAuthn/FIDO2 support |

## Recommended technology stack
### Web client
- React with TypeScript
- `shadcn/ui` for accessible UI building blocks
- Tailwind CSS for responsive layout and design tokens
- Zustand for local UI and vault-session state
- TanStack Query for server state, sync status, and mutations
- React Hook Form plus Zod for validation-heavy forms such as sign-in, enrollment, device approval, and recovery
- Web Crypto API for client-side encryption and decryption
- IndexedDB for local encrypted cache
- WebAuthn/FIDO2 browser APIs for passkeys and YubiKey flows

### Backend
- ASP.NET Core .NET 10 Web API
- Entity Framework Core for a straightforward data-access layer
- PostgreSQL as the primary application database
- Redis only if needed later for rate limiting, distributed caching, or short-lived approval challenges
- password-derived verifier authentication with pinned Argon2id defaults: `m=64MB`, `t=3`, `p=4`

### Reasonable but simple backend storage
For a simple but solid MVP, use a single PostgreSQL database.

Store:
- users
- devices
- encrypted vault entries
- wrapped vault keys and recovery-code hashes
- WebAuthn credential records
- audit events

Why PostgreSQL:
- simple operational model for an MVP
- strong relational fit for users, devices, approvals, and audit trails
- reliable transactions for sync and recovery flows
- JSON support where a little schema flexibility is useful

What to avoid early:
- separate document database
- event store
- blob storage for normal vault records
- Redis as a hard dependency unless traffic or challenge workflows clearly justify it

### Minimal PostgreSQL schema
Keep the schema small. A good MVP needs about seven core tables.

#### `users`
- `id` UUID primary key
- `email` text unique not null
- `password_verifier` bytea not null
- `password_kdf_config` jsonb not null
- `created_at` timestamptz not null
- `updated_at` timestamptz not null
- `last_login_at` timestamptz null

Purpose:
- account identity
- password-derived verifier authentication
- storing pinned KDF parameters used for verifier derivation and password-based vault unwrap

#### `devices`
- `id` UUID primary key
- `user_id` UUID not null references `users(id)`
- `device_name` text not null
- `platform` text not null
- `client_type` text not null
- `status` text not null
- `device_public_key` text null
- `created_at` timestamptz not null
- `approved_at` timestamptz null
- `last_seen_at` timestamptz null
- `revoked_at` timestamptz null

Purpose:
- tracks approved, pending, and revoked devices
- supports device approval and device-specific vault-key wrapping

Note:
- `device_public_key` may be null only before a device has completed key registration; approved devices must have a non-null key

#### `vault_entries`
- `id` UUID primary key
- `user_id` UUID not null references `users(id)`
- `entry_payload` bytea not null
- `entry_version` integer not null
- `created_at` timestamptz not null
- `updated_at` timestamptz not null
- `deleted_at` timestamptz null

Purpose:
- stores encrypted TOTP records
- supports soft delete and optimistic sync

Note:
- `entry_payload` should be a single AEAD blob containing nonce plus ciphertext for issuer, account name, secret, algorithm, digits, and period
- server-side search is intentionally not supported for vault contents

#### `vault_key_envelopes`
- `id` UUID primary key
- `user_id` UUID not null references `users(id)`
- `device_id` UUID null references `devices(id)`
- `envelope_type` text not null
- `wrapped_key_payload` bytea not null
- `created_at` timestamptz not null
- `revoked_at` timestamptz null

Purpose:
- stores wrapped forms of the same vault key
- one row for password-based unwrap path
- one row per approved device
- optionally one row for recovery-assisted rewrap workflows

Note:
- use the same convention as `vault_entries`: `wrapped_key_payload` is a single AEAD blob containing nonce plus ciphertext

Recommended `envelope_type` values:
- `password`
- `device`
- `recovery`

#### `recovery_codes`
- `id` UUID primary key
- `user_id` UUID not null references `users(id)`
- `code_hash` text not null
- `code_slot` integer not null
- `created_at` timestamptz not null
- `used_at` timestamptz null
- `replaced_at` timestamptz null

Purpose:
- stores only hashed recovery codes
- supports one-time use and full rotation

#### `webauthn_credentials`
- `id` UUID primary key
- `user_id` UUID not null references `users(id)`
- `credential_id` bytea unique not null
- `public_key` bytea not null
- `sign_count` bigint null
- `friendly_name` text null
- `transports` jsonb null
- `created_at` timestamptz not null
- `last_used_at` timestamptz null
- `revoked_at` timestamptz null

Purpose:
- stores YubiKey or other WebAuthn credential registrations
- enables strong recovery step-up and security-sensitive approvals

#### `audit_events`
- `id` UUID primary key
- `user_id` UUID null references `users(id)`
- `device_id` UUID null references `devices(id)`
- `event_type` text not null
- `event_data` jsonb null
- `ip_address` text null
- `user_agent` text null
- `created_at` timestamptz not null

Purpose:
- records logins, approvals, recovery attempts, key enrollments, revocations, and suspicious events

### Optional later tables
- `device_approval_requests` if approval flows become complex enough that pending approvals deserve first-class storage
- `refresh_sessions` if you want explicit server-managed session revocation
- `rate_limit_buckets` only if database-backed throttling is needed before adding Redis

### Minimal indexing guidance
- unique index on `users(email)`
- index on `devices(user_id, status)`
- index on `vault_entries(user_id, deleted_at)`
- unique index on `vault_key_envelopes(user_id, device_id, envelope_type)` with null-aware handling for password rows
- index on `recovery_codes(user_id, used_at, replaced_at)`
- unique index on `webauthn_credentials(credential_id)`
- index on `audit_events(user_id, created_at desc)`

### Offline sync conflict policy
Use a simple explicit policy from day one: **last-write-wins per vault entry**, using server-assigned `updatedAt` plus `entryVersion`.

Rules:
- the full encrypted vault syncs to every client
- edits operate on one entry at a time
- concurrent updates to the same entry resolve by accepting the latest committed write
- deletes are soft deletes and participate in the same version ordering
- client UI should warn when a local pending change loses a conflict
- first-time device enrollment requires connectivity; offline mode is only available after at least one successful sync on that device

Rationale:
- acceptable for a small personal TOTP vault
- simple enough for MVP
- avoids undefined offline behavior

### Soft-delete retention policy
- keep soft-deleted entries for sync correctness and conflict handling
- purge tombstones after a conservative retention period such as 30 days once all active devices have had a chance to sync
- audit events should outlive tombstone cleanup

## Mobile app-lock policy
The mobile client should have a local app-lock layer separate from account authentication.

### Purpose
- protect already-synced vault contents on a physically accessible device
- reduce risk from casual device access after the user has already enrolled and synced
- ensure local TOTP generation requires fresh user presence after lock conditions

### Recommended defaults
- require biometric authentication on app open when available
- allow Android device credential fallback through the system prompt
- auto-lock after app backgrounding for more than a short timeout
- lock immediately after device reboot
- lock immediately after explicit user lock or logout
- require unlock before displaying TOTP codes or allowing copy actions

### Vault access model
- `VaultKey` unwrap on Android should be gated through Android Keystore
- when supported, the Keystore key should require user authentication for each unlock session
- decrypted vault material should remain in memory only while the app is unlocked
- app lock should clear sensitive in-memory state on lock

### Timeout policy
Recommended MVP defaults:
- immediate lock on app restart
- immediate lock on device reboot
- configurable inactivity timeout with a secure default such as 30 to 60 seconds after backgrounding

### Failure handling
- rely on Android system biometric and device-credential throttling rather than implementing a custom PIN system in MVP
- if biometric authentication is unavailable or revoked, fall back to Android device credential if policy allows
- if neither is available, require full account re-authentication and disallow persistent unlocked state

### UX notes
- show clear locked state UI rather than stale account data
- avoid rendering live TOTP codes in app switcher previews by using Android secure-window protections such as `FLAG_SECURE`
- provide an explicit "Lock now" action in the app menu

## Web lock policy
The web client should also have an explicit local lock model once the vault has been decrypted in memory.

### Purpose
- reduce risk when a user leaves an unlocked browser tab open
- ensure decrypted vault state is not retained indefinitely in a live session

### Recommended defaults
- auto-lock after a short inactivity timeout, such as 3 to 5 minutes
- clear decrypted in-memory vault state on lock
- require explicit re-unlock before showing codes or allowing copy actions after lock
- provide a visible "Lock now" action in the UI

### Rules
- password-only web sessions may decrypt the vault for the current session but must not persist unwrap material
- WebAuthn-backed web sessions may persist approved device unwrap material, but decrypted vault contents must still be cleared on lock
- lock should trigger on explicit user action, inactivity timeout, logout, and refresh or full tab close unless a secure re-unlock path is immediately available

### UX notes
- the locked state should hide codes and sensitive account metadata until re-unlock
- the inactivity timeout should reset on meaningful user interaction, not on passive countdown rendering
- the timeout value can become configurable later, but MVP should ship with a secure default

## Core security flows
These flows should be treated as the reference behavior for backend API design, client state, and audit logging.

### 1. First-device bootstrap
Goal:
- create the user account
- create the initial vault key
- establish the first approved device

Flow:
1. User chooses an email and password locally.
2. Web client generates a random `VaultKey` locally.
3. Web client derives:
   - a password verifier using pinned Argon2id settings
   - a password-based unwrap key using the same password input
4. Web client wraps `VaultKey` with the password-based unwrap key and prepares a `password` envelope.
5. Web client generates or requests device key material for the current device and wraps `VaultKey` again as a `device` envelope.
6. Server creates:
   - `users` row
   - `devices` row with `status = approved`
   - `vault_key_envelopes` rows for password and current device
   - password verifier material, not the raw password
7. Client offers immediate setup of:
   - recovery codes
   - hardware security key registration
8. Client stores only local encrypted cache and device-protected unwrap material, never plaintext secrets on the server.

Important rules:
- the first device becomes trusted automatically because there is no prior device to approve it
- recovery setup should be strongly encouraged before the user can consider the account fully protected
- audit event should capture account creation and first-device enrollment

### 2. Web vault unlock on an approved device
Goal:
- decrypt local or synced vault data on a previously approved device

Preferred flow:
1. User signs in.
2. Client restores session metadata and encrypted vault cache from IndexedDB.
3. Client attempts to access device-protected unwrap material.
4. In the browser, persistent device unwrap material is only allowed for WebAuthn-backed approved devices.
5. If the device requires biometric or platform-auth confirmation, the browser or OS prompts for it where supported.
6. Client unwraps `VaultKey` using the device path.
7. Client decrypts vault entries locally and starts local TOTP generation.

Password-only browser session flow:
1. User completes login using the password-derived verifier flow.
2. Client derives the password unwrap key locally.
3. Client unwraps the `password` envelope and reconstructs `VaultKey`.
4. Client decrypts vault entries locally for the current session only.
5. Client must not persist new unwrap material unless WebAuthn-backed approval has completed.

Fallback flow:
1. If device unwrap is unavailable, the client uses the password-based local unwrap path.
2. Client derives the password key with stored KDF parameters.
3. Client unwraps the `password` envelope and reconstructs `VaultKey`.
4. Client decrypts vault entries locally.

Important rules:
- server never receives plaintext TOTP secrets or plaintext vault key
- server never receives the raw password
- unlocked state should be time-bounded and cleared on explicit lock, logout, or sufficiently sensitive events
- audit event should capture successful and failed unlock attempts that involve server-visible auth state

### 3. Add and approve a second device
Goal:
- allow a new device to join only after password authentication and approval from an already trusted device

Flow:
1. User signs in on a new device using the password-derived verifier flow.
2. Server creates a `devices` row with `status = pending`.
3. New device generates its own device key material or public key needed for wrapping workflow.
4. Server records a device-approval request and notifies existing approved devices if possible.
5. On an approved device, user reviews:
   - pending device name
   - platform
   - approximate location or IP metadata if available
   - request time
6. Approved device requires re-authentication for the approval action:
   - password re-entry, or
   - hardware security key / WebAuthn step-up
7. Approved device, after unlocking its own vault, obtains `VaultKey` locally.
8. Approved device wraps `VaultKey` for the pending device and submits the new `device` envelope to the server.
9. Server marks the pending device as `approved`.
10. New device fetches its device-specific envelope, unwraps `VaultKey`, and can now decrypt synced vault entries locally.

Important rules:
- password alone is not enough to activate a new device after the first device
- approval requests should expire quickly
- approval and rejection actions must be audited
- first login on a brand-new device cannot complete offline because approval state, envelopes, and vault sync all require server connectivity

### 4. Last-device recovery with recovery codes
Goal:
- recover access when no approved device remains, without relying on email alone

Flow:
1. User starts recovery and authenticates to the account at the account level.
2. User submits a recovery code.
3. Server verifies the code against a stored hash and marks it one-time reserved.
4. Server requires additional step-up such as the password-derived verifier flow and optional WebAuthn challenge.
5. Server starts a recovery hold period and sends notifications to all known devices and the account email.
6. After the hold expires and no cancellation occurs, the server authorizes release of encrypted recovery material.
7. Client generates new device key material for the replacement device.
8. Client or recovery service path re-establishes access to `VaultKey` according to the chosen recovery design.
9. User is forced to:
   - rotate remaining recovery codes
   - review devices
   - review audit history

Important design note:
- if recovery codes are meant to restore the vault itself, the design must include a cryptographically valid recovery path for `VaultKey`, not just account access
- this can be done by maintaining a dedicated recovery envelope or equivalent recovery-unwrapping mechanism
- recommended recovery hold for MVP: 24 to 48 hours, with explicit cancellation ability from any still-trusted device

### 5. Last-device recovery with hardware security key
Goal:
- allow a registered hardware security key to satisfy high-trust recovery or approval requirements

Entry point:
- hardware-key recovery is not a separate unauthenticated path
- it is an optional or required step inside the same recovery session started by `POST /api/recovery/codes/redeem`

Flow:
1. User starts recovery on a new device.
2. Server challenges the registered WebAuthn credential.
3. User completes the challenge with YubiKey or another compatible security key.
4. Server verifies the assertion and confirms that the security key is valid and not revoked.
5. Recovery proceeds to the vault-restoration path:
   - re-authorize a recovery envelope, or
   - allow a controlled rewrap for a new approved device, depending on final crypto design
6. User completes password step-up if policy requires both knowledge and possession factors.
7. New device receives approved-device status and a usable device envelope for `VaultKey`.

Important rules:
- hardware security key should be treated as a strong recovery factor, but not a substitute for sound vault-key recovery design
- credential enrollment, use, and revocation must all be audited

### 6. Password change
Goal:
- allow the user to replace the account password without changing the vault contents

Flow:
1. User unlocks the vault on an approved device.
2. User completes step-up authentication with the current password-derived verifier flow.
3. Client derives:
   - new `PasswordVerifier`
   - new password envelope key
4. Client unwraps `VaultKey` locally with the current approved path.
5. Client rewraps `VaultKey` into a new `password` envelope.
6. Server atomically replaces:
   - stored password verifier
   - password KDF config if changed
   - password envelope row
7. Existing approved device envelopes remain valid.
8. Refresh sessions are rotated or revoked according to session policy.

Important rules:
- password change must be atomic
- failure must not leave the account with mismatched verifier and password envelope
- recovery artifacts should remain valid unless the user chooses full security rotation

### 7. Device revocation
Goal:
- remove a device’s future access without corrupting the user’s vault

Flow:
1. User selects an approved device to revoke from a still-trusted device or recovery session.
2. System requires step-up authentication for revocation.
3. Server sets `devices.status = revoked` and timestamps `revoked_at`.
4. Server revokes the matching `device` envelope in `vault_key_envelopes`.
5. Future sync or unlock requests from that device are denied.
6. User is prompted to rotate recovery artifacts if the revocation was caused by suspected compromise.

Important rules:
- revocation prevents future unwraps and sync, but cannot erase secrets already decrypted on an attacker-controlled device
- user-facing messaging should explain that revocation limits future access, not past exposure

## VaultKey recovery design
### Recommendation
Use a **dedicated recovery envelope**.

That means the system keeps one extra wrapped form of `VaultKey`, separate from:
- the password envelope
- device envelopes

This recovery envelope is not directly usable on its own. It can only be released or rewrapped after successful recovery-factor validation.

### Why this is the best fit
It keeps the model understandable:
- password unlocks normal access
- approved devices unlock normal multi-device usage
- recovery codes or YubiKey unlock the emergency recovery path

It also avoids a dead-end design where recovery factors prove identity but still cannot actually restore the vault.

### Recommended model
At bootstrap, the client creates:
- one `password` envelope
- one `device` envelope for the current device
- one `recovery` envelope for emergency recovery

The `recovery` envelope should be encrypted with a dedicated `RecoveryKey`.

Recommended structure:
1. Generate random `VaultKey`
2. Generate random `RecoveryKey`
3. Wrap `VaultKey` with `RecoveryKey` and store that as the `recovery` envelope
4. Split access to `RecoveryKey` across recovery factors

### Simple practical way to protect `RecoveryKey`
For the MVP, use this policy:
- recovery codes authorize recovery flow
- registered YubiKey authorizes recovery flow
- password is still required as a step-up factor during recovery
- once policy checks pass, the server releases a recovery-wrapped package to the client
- client reconstructs or unwraps `RecoveryKey`
- client unwraps `VaultKey`
- client creates a new `device` envelope for the replacement device

### Important implementation detail
The server must never store `RecoveryKey` in plaintext.

Instead, store only protected forms, for example:
- a recovery-key package encrypted for a recovery-code-derived key
- a recovery-key package encrypted for a hardware-key-approved recovery session
- or an equivalent design where the server stores only ciphertext and policy metadata

### Recommended MVP approach
The simplest reasonable MVP is:

1. Derive a **Recovery Unlock Key** from a high-entropy recovery secret generated at bootstrap
2. Use that key to encrypt `RecoveryKey`
3. Represent that recovery secret to the user as:
   - printable recovery codes, or
   - one recovery kit that can regenerate those codes
4. Store only hashed recovery codes for verification and only ciphertext for the wrapped recovery material
5. Treat YubiKey as a required or optional step-up factor that authorizes release of the recovery package, not as the only carrier of vault recovery material

### Why not make YubiKey the only recovery carrier?
Because WebAuthn credentials are excellent for:
- authentication
- challenge signing
- step-up approval

But they are awkward as the sole portable container for secret recovery material across all clients and future device states.

So the cleaner design is:
- **recovery codes carry recoverability**
- **YubiKey strengthens authorization**

### Concrete recovery flow
1. User starts last-device recovery.
2. User signs in at the account level.
3. User provides one valid recovery code.
4. Server verifies the code hash and marks it consumed.
5. If policy requires YubiKey, server runs a WebAuthn challenge and verifies it.
6. If policy requires password re-entry, user completes it.
7. Server releases the encrypted recovery package tied to the recovery flow.
8. Client derives the Recovery Unlock Key from the recovery material.
9. Client unwraps `RecoveryKey`.
10. Client uses `RecoveryKey` to unwrap `VaultKey`.
11. Client generates a new device key and creates a new `device` envelope.
12. Client rotates recovery artifacts immediately after success.

### Security properties
This gives:
- no plaintext TOTP secrets on the server
- no plaintext `VaultKey` on the server
- recovery that actually works after the last device is lost
- ability to require multiple factors for recovery

### Tradeoff
This design slightly weakens pure device-only trust because a dedicated emergency recovery path exists.

That tradeoff is acceptable if:
- recovery artifacts are high entropy
- recovery codes are one-time use
- recovery events are heavily audited
- users are prompted to rotate recovery material after any recovery

### Recommendation for the plan
Adopt this explicit policy:
- normal path: approved device or password
- new device path: password plus approved-device authorization
- emergency path: recovery code plus password, optionally strengthened with YubiKey
- YubiKey is a strong recovery gate, but not the sole mechanism that makes vault recovery possible

## Exact recovery artifact format
### Recommendation
Use a **single recovery kit** generated at bootstrap, plus a set of one-time recovery codes derived from it for day-to-day emergency use.

This keeps the UX manageable:
- users can print or save recovery codes
- the system still has one canonical recovery secret underneath
- rotation is possible without changing the whole vault design

### Artifact components
The recovery design should use these pieces:

#### 1. Recovery Seed
A high-entropy random secret generated on the client at bootstrap.

Recommended properties:
- 32 bytes random minimum
- displayed only once to the user in recovery-kit form
- never stored server-side in plaintext

Purpose:
- root secret for emergency recovery
- input to derive a Recovery Unlock Key
- source material for generating printable recovery codes

#### 2. Recovery Unlock Key
A derived symmetric key created from the Recovery Seed.

Recommended derivation:
- HKDF-SHA-256 from the Recovery Seed
- fixed context string such as `totp-vault-recovery-unlock-v1`

Purpose:
- encrypt or decrypt `RecoveryKey`

#### 3. RecoveryKey
A random symmetric key generated locally.

Purpose:
- wraps `VaultKey`
- separates vault recoverability from the raw recovery seed itself

#### 4. Recovery envelope
Encrypted package containing `RecoveryKey`, protected by the Recovery Unlock Key.

Suggested payload before encryption:

```json
{
  "version": 1,
  "userId": "uuid",
  "recoveryKey": "base64",
  "createdAt": "ISO-8601 timestamp"
}
```

Stored server-side as:
- `recovery_envelope_ciphertext`
- `recovery_envelope_nonce`
- `recovery_envelope_version`

#### 5. Recovery codes
A fixed-size list of one-time codes shown to the user.

Recommended properties:
- 8 to 12 codes
- each code 10 to 16 characters
- generated from secure random bytes, not user-chosen text
- stored on the server only as slow hashes

Purpose:
- authorize emergency recovery
- prove the user still possesses recovery material

### What the user receives
The user should receive two recovery artifacts during setup:

#### A. Printable recovery codes
Example format:

```text
RC-4F8K-9Q2M
RC-7T1P-LX6D
RC-2W3N-HV8R
```

These are:
- easy to print
- one-time use
- intended for fast emergency recovery

#### B. Full recovery kit
This can be displayed as:
- a long base32 or base64url recovery secret, or
- a downloadable encrypted recovery file for later import

For MVP simplicity, prefer:
- printable one-time recovery codes for users
- no downloadable file unless you intentionally want more operational complexity

### What the server stores
Server stores:
- hashed recovery codes
- encrypted recovery envelope
- metadata such as version, created time, rotated time, and consumption status

Server does **not** store:
- Recovery Seed in plaintext
- Recovery Unlock Key in plaintext
- RecoveryKey in plaintext
- VaultKey in plaintext

### What the client stores locally
Normally, the client should not persist the Recovery Seed automatically.

Recommended behavior:
- show recovery codes once
- strongly prompt the user to print or save them offline
- allow explicit regeneration only after step-up authentication

### Code format recommendation
Keep recovery codes independent from direct key material.

Recommended approach:
- recovery codes are random one-time tokens
- code verification proves recovery entitlement
- successful verification allows the server to release the encrypted recovery envelope
- the actual Recovery Unlock Key is derived from the Recovery Seed or equivalent kit secret held by the user

This means there are two possible MVP variants:

#### Simpler MVP
- recovery codes themselves are the only user-held recovery material
- one valid code plus password allows release of a recovery package
- client derives Recovery Unlock Key from the redeemed code plus server metadata

Pros:
- simpler UX

Cons:
- each code becomes both authorizer and cryptographic input
- code rotation is more tightly coupled to recovery encryption material

#### Better MVP
- recovery codes authorize the flow
- one separate Recovery Seed or recovery kit provides cryptographic input

Pros:
- cleaner crypto model
- easier code rotation without re-encrypting the whole recovery chain

Cons:
- slightly more complex UX

### Recommended final choice
Use the **better MVP**:
- recovery codes = authorization artifact
- Recovery Seed = cryptographic recovery artifact

This is the cleanest design if you want future flexibility.

### Recovery artifact lifecycle
#### Bootstrap
1. Client generates `RecoverySeed`
2. Client derives Recovery Unlock Key
3. Client generates `RecoveryKey`
4. Client wraps `VaultKey` with `RecoveryKey`
5. Client wraps `RecoveryKey` with the Recovery Unlock Key
6. Client generates one-time recovery codes
7. Server stores:
   - recovery envelope ciphertext
   - recovery code hashes
   - metadata
8. User saves:
   - printed recovery codes
   - Recovery Seed or equivalent recovery kit

#### Recovery
1. User enters account credentials
2. User redeems one recovery code
3. User provides Recovery Seed or imports recovery kit
4. Server releases encrypted recovery envelope after policy checks
5. Client derives Recovery Unlock Key
6. Client unwraps `RecoveryKey`
7. Client unwraps `VaultKey`
8. Client creates a new device envelope

#### Rotation
Rotate recovery artifacts when:
- any recovery code is used
- user suspects compromise
- user revokes a suspicious device

Rotation should:
- invalidate all remaining recovery codes
- generate a new Recovery Seed
- generate a new RecoveryKey
- rewrap `VaultKey` into a fresh recovery envelope
- issue a new recovery-code set

### Recommended database shape additions
Add or clarify these fields under recovery storage:
- `recovery_envelope_ciphertext` bytea
- `recovery_envelope_nonce` bytea
- `recovery_envelope_version` integer
- `recovery_rotated_at` timestamptz

If you keep recovery material separate from `vault_key_envelopes`, create a dedicated `vault_recovery_material` table. Otherwise, keep it as a `recovery` row in `vault_key_envelopes` plus related metadata.

## Initial API contract
The API should stay boring and explicit. The backend is an encrypted sync and policy service, not the generator of TOTP codes.

### Conventions
- JSON over HTTPS
- bearer access token for authenticated calls (mobile), httpOnly cookie for web clients
- all timestamps in ISO-8601 UTC
- all binary values encoded as standard base64 in JSON (uses `Convert.ToBase64String`, not base64url)
- optimistic concurrency via `entryVersion` or `If-Match` style version fields

### Token delivery: dual mode (web cookies / mobile bearer)
Web clients (`clientType: "web"`) receive access and refresh tokens as httpOnly cookies to prevent XSS token theft. Mobile/native clients receive tokens in the JSON response body and send the access token via `Authorization: Bearer` header.

| Cookie | Name | Path | MaxAge | HttpOnly | Secure | SameSite |
|--------|------|------|--------|----------|--------|----------|
| Access token | `__Host-access_token` | `/` | 15 min | yes | yes | Strict |
| Refresh token | `__Host-refresh_token` | `/api/auth` | 30 days | yes | yes | Strict |

The JWT middleware extracts the access token from the cookie via `OnMessageReceived`, falling back to the Bearer header. This makes auth transparent to all protected endpoints — no middleware changes needed per-route.

The refresh token cookie uses a restricted path (`/api/auth`) so it is only sent to auth endpoints, reducing exposure on regular API calls.

### Password-derived verifier proof construction
For the MVP, use an explicit verifier-based challenge-response, not a hand-wavy custom proof.

Recommended construction:
1. Client derives `PasswordAuthKey` from the password using pinned Argon2id parameters.
2. Client derives:
   - `PasswordVerifier = HKDF(PasswordAuthKey, "auth-verifier-v1")`
   - `PasswordEnvelopeKey = HKDF(PasswordAuthKey, "vault-password-envelope-v1")`
3. Server stores only `PasswordVerifier`.
4. During login, server returns a fresh nonce.
5. Client computes `clientProof = HMAC-SHA-256(PasswordVerifier, nonce || loginSessionId)`.
6. Server recomputes the same value from the stored verifier and compares in constant time.

Notes:
- this is a verifier-based challenge-response, not SRP
- it prevents sending the raw password to the server
- if mutual authentication is later required, the plan can evolve to SRP or OPAQUE
- accepted MVP tradeoff: a database breach exposing stored password verifiers would allow authentication impersonation, but would still not reveal plaintext vault contents without the actual password-derived envelope key

### Authentication and bootstrap
#### `POST /api/auth/register/begin`
Starts registration and email verification.

Response:
```json
{
  "registrationSessionId": "uuid",
  "emailVerificationRequired": true
}
```

#### `POST /api/auth/register/verify-email`
Confirms the email ownership token for the registration session.

#### `POST /api/auth/register`
Creates the account and first approved device.

Request:
```json
{
  "email": "alice@example.com",
  "passwordVerifier": {
    "verifier": "base64url",
    "kdf": {
      "algorithm": "argon2id",
      "memoryMb": 64,
      "iterations": 3,
      "parallelism": 4
    }
  },
  "passwordEnvelope": {
    "ciphertext": "base64url",
    "nonce": "base64url",
    "version": 1
  },
  "device": {
    "deviceName": "Alice Web Chrome",
    "platform": "web",
    "clientType": "web",
    "devicePublicKey": "base64url"
  },
  "deviceEnvelope": {
    "ciphertext": "base64url",
    "nonce": "base64url",
    "version": 1
  },
  "recovery": {
    "recoveryEnvelopeCiphertext": "base64url",
    "recoveryEnvelopeNonce": "base64url",
    "recoveryEnvelopeVersion": 1,
    "recoveryCodeHashes": [
      "argon2-hash-1",
      "argon2-hash-2"
    ]
  }
}
```

Response (mobile — tokens in body):
```json
{
  "userId": "uuid",
  "deviceId": "uuid",
  "accessToken": "jwt-or-reference-token",
  "refreshToken": "opaque-token"
}
```

Response (web — tokens in httpOnly cookies, `clientType: "web"`):
```json
{
  "userId": "uuid",
  "deviceId": "uuid",
  "accessToken": null,
  "refreshToken": null
}
```
The access token is set as `__Host-access_token` (httpOnly, Secure, SameSite=Strict, Path=/) and the refresh token as `__Host-refresh_token` (httpOnly, Secure, SameSite=Strict, Path=/api/auth). Web clients never receive tokens in the response body.

#### `POST /api/auth/login`
Starts the password-derived verifier challenge flow.

Request:
```json
{
  "email": "alice@example.com",
  "device": {
    "deviceName": "New Laptop",
    "platform": "web",
    "clientType": "web",
    "devicePublicKey": "base64url"
  }
}
```

Response:
```json
{
  "loginSessionId": "uuid",
  "challenge": {
    "nonce": "base64url",
    "kdf": {
      "algorithm": "argon2id",
      "memoryMb": 64,
      "iterations": 3,
      "parallelism": 4
    }
  }
}
```

For unknown emails:
- return the same response shape with fake KDF parameters and indistinguishable timing to reduce user enumeration risk

#### `POST /api/auth/login/complete`
Completes the password-derived verifier challenge and returns session state.

Request:
```json
{
  "loginSessionId": "uuid",
  "clientProof": "base64url"
}
```

Response for approved device (mobile — tokens in body; web — tokens in httpOnly cookies, fields are null):
```json
{
  "accessToken": "token",
  "refreshToken": "token",
  "device": {
    "deviceId": "uuid",
    "status": "approved",
    "persistentKeyAllowed": true
  },
  "envelopes": {
    "password": {
      "ciphertext": "base64url",
      "nonce": "base64url",
      "version": 1
    },
    "device": {
      "ciphertext": "base64url",
      "nonce": "base64url",
      "version": 1
    }
  }
}
```

Response for pending device (same token delivery rules):
```json
{
  "accessToken": "token",
  "refreshToken": "token",
  "device": {
    "deviceId": "uuid",
    "status": "pending",
    "persistentKeyAllowed": false
  },
  "approvalRequestId": "uuid"
}
```

### Vault sync
#### `GET /api/vault`
Returns encrypted vault entries and sync metadata for the current user.

Response:
```json
{
  "entries": [
    {
      "id": "uuid",
      "entryPayload": "base64url",
      "entryVersion": 3,
      "deletedAt": null,
      "updatedAt": "2026-04-01T18:00:00Z"
    }
  ],
  "serverTime": "2026-04-01T18:00:00Z"
}
```

#### `PUT /api/vault/{entryId}`
Creates or updates one encrypted vault entry.

Request:
```json
{
  "entryPayload": "base64url",
  "entryVersion": 3
}
```

Response:
```json
{
  "id": "uuid",
  "entryVersion": 4,
  "updatedAt": "2026-04-01T18:00:00Z"
}
```

#### `DELETE /api/vault/{entryId}`
Soft-deletes a vault entry.

### Device management and approval
#### `GET /api/devices`
Lists current devices and pending approvals.

Response:
```json
{
  "devices": [
    {
      "deviceId": "uuid",
      "deviceName": "Alice Web Chrome",
      "platform": "web",
      "status": "approved",
      "approvedAt": "2026-04-01T18:00:00Z"
    },
    {
      "deviceId": "uuid",
      "deviceName": "New Laptop",
      "platform": "web",
      "status": "pending",
      "approvalRequestId": "uuid",
      "devicePublicKey": "base64url",
      "requestedAt": "2026-04-01T18:05:00Z"
    }
  ]
}
```

#### `POST /api/devices/{deviceId}/approve`
Approves a pending device after step-up auth on an approved device.

Request:
```json
{
  "approvalRequestId": "uuid",
  "approvalAuth": {
    "type": "password-or-webauthn"
  },
  "deviceEnvelope": {
    "ciphertext": "base64url",
    "nonce": "base64url",
    "version": 1
  }
}
```

Response:
```json
{
  "deviceId": "uuid",
  "status": "approved"
}
```

#### `POST /api/devices/{deviceId}/reject`
Rejects a pending device approval request.

#### `POST /api/devices/{deviceId}/revoke`
Revokes an approved device after step-up auth.

### Recovery codes
#### `POST /api/recovery/codes/regenerate`
Generates a fresh recovery-code set after step-up auth.

Response:
```json
{
  "recoveryCodes": [
    "RC-4F8K-9Q2M",
    "RC-7T1P-LX6D"
  ],
  "rotatedAt": "2026-04-01T18:00:00Z"
}
```

#### `POST /api/recovery/codes/redeem`
Consumes one recovery code and opens a recovery session.

Request:
```json
{
  "email": "alice@example.com",
  "recoveryCode": "RC-4F8K-9Q2M",
  "verifierProof": {
    "loginSessionId": "uuid",
    "clientProof": "base64url"
  }
}
```

Response:
```json
{
  "recoverySessionId": "uuid",
  "requiresWebAuthn": true,
  "releaseEarliestAt": "2026-04-02T18:00:00Z"
}
```

### Recovery session
#### `POST /api/recovery/session/{recoverySessionId}/webauthn/begin`
Starts optional or required WebAuthn step-up.

#### `POST /api/recovery/session/{recoverySessionId}/webauthn/complete`
Completes WebAuthn step-up.

#### `POST /api/recovery/session/{recoverySessionId}/material`
Returns encrypted recovery material after all required checks pass.

Request:
```json
{
  "replacementDevice": {
    "deviceName": "Replacement Laptop",
    "platform": "web",
    "clientType": "web",
    "devicePublicKey": "base64url"
  }
}
```

Response:
```json
{
  "status": "ready",
  "recoveryEnvelope": {
    "ciphertext": "base64url",
    "nonce": "base64url",
    "version": 1
  },
  "replacementDeviceId": "uuid"
}
```

Response while the hold period is still active:
```json
{
  "status": "pending",
  "releaseEarliestAt": "2026-04-02T18:00:00Z"
}
```

#### `POST /api/recovery/session/{recoverySessionId}/complete`
Finalizes recovery after the client has recreated a new device envelope.

Request:
```json
{
  "replacementDeviceId": "uuid",
  "deviceEnvelope": {
    "ciphertext": "base64url",
    "nonce": "base64url",
    "version": 1
  },
  "rotatedRecovery": {
    "recoveryEnvelopeCiphertext": "base64url",
    "recoveryEnvelopeNonce": "base64url",
    "recoveryEnvelopeVersion": 1,
    "recoveryCodeHashes": [
      "argon2-hash-1",
      "argon2-hash-2"
    ]
  }
}
```

### WebAuthn
#### `POST /api/webauthn/register/begin`
Starts registration of a YubiKey or other WebAuthn credential.

#### `POST /api/webauthn/register/complete`
Stores the credential after client attestation response.

#### `POST /api/webauthn/assert/begin`
Starts a challenge for approval or recovery step-up.

#### `POST /api/webauthn/assert/complete`
Verifies the signed assertion.

### Audit and session support
#### `GET /api/security/audit-events`
Returns recent audit history for display in the web app.

#### `POST /api/auth/refresh`
Rotates and returns a new access + refresh token pair.

Token source:
- web clients: refresh token read from `__Host-refresh_token` cookie (body may be empty)
- mobile clients: refresh token sent in request body

Token delivery follows the same dual mode as login: web clients receive new tokens as httpOnly cookies (body fields are null), mobile clients receive tokens in the response body.

Refresh token policy:
- use opaque server-stored refresh tokens
- rotate on every successful refresh
- revoke the previous refresh token on rotation
- revoke the current refresh token on logout
- expire refresh tokens after a bounded period such as 30 days, with shorter idle expiry if desired

#### `POST /api/auth/logout`
Ends the current session. Reads refresh token from cookie or body (same as refresh). Clears both token cookies regardless of client type.

#### `POST /api/account/password/change`
Atomically updates the password verifier and password envelope after local rewrap.

#### `DELETE /api/account`
Account deletion is intentionally deferred from MVP unless compliance or product requirements make it mandatory earlier.

### Notes
- the API never accepts plaintext TOTP values
- the API never generates OTP codes for the client
- the API never accepts the raw password
- all crypto payloads should include explicit version fields
- recovery endpoints should be aggressively rate-limited and heavily audited
- recovery material release should be delayed, cancellable, and notified

## Implementation Steps
### Phase 1: Requirements and security baseline
- Document the product scope in `docs/architecture/` or the chosen design location for:
  - responsive React web client runnable on desktop and mobile-sized screens
  - Android companion client
  - ASP.NET Core .NET 10 backend
  - Single user with multiple devices, not team sharing
- Write a threat model covering:
  - stolen password
  - stolen unlocked device
  - stolen encrypted server database
  - malicious email recovery attempt
  - replay or tampering during sync
- Define the minimum vault record shape:

```json
{
  "id": "uuid",
  "entryPayload": "base64url-aead-blob",
  "version": 1
}
```

- `entryPayload` is a single encrypted AEAD blob containing nonce plus ciphertext for issuer, account name, TOTP secret, algorithm, digits, and period.

- Store vault records as encrypted `entryPayload` blobs from day one, including issuer, account name, TOTP secret, algorithm, digits, and period.
- Define non-functional requirements:
  - offline code generation
  - eventual sync after reconnect
  - explicit last-write-wins conflict handling per entry
  - first-time device enrollment requires connectivity; offline mode begins only after a successful sync on that device
  - bounded clock drift tolerance
  - audit retention period
  - recovery code issuance, rotation, and lockouts
  - hardware security key enrollment limits and recovery policy
- Create individual test files (one test per file):
  - `tests/architecture/test_vault_record_contract.md` or equivalent design-validation artifact if this phase is documentation-only
  - `tests/security/test_threat_model_coverage.md`
  - `tests/security/test_email_verification_flow.cs`
  - `tests/security/test_login_enumeration_resistance.cs`
- Run tests to verify:
  - use the repository’s existing validation or documentation review process

### Phase 2: Cryptography and key hierarchy
- Design a key hierarchy where TOTP entries are encrypted with a random vault key:
  - `VaultKey` encrypts all TOTP secrets
  - password-derived key unwraps `VaultKey`
  - per-device key wraps `VaultKey` for approved-device reuse
- Use a modern KDF for the password path:
  - Argon2id required for MVP
  - pin defaults to `m=64MB`, `t=3`, `p=4`
- Use an AEAD for entry encryption:
  - AES-GCM or XChaCha20-Poly1305
- Define server-side persisted objects:
  - encrypted vault entries
  - wrapped vault key for password-authenticated access
  - wrapped vault key per approved device
  - recovery code hashes and metadata
  - hardware security key credentials and enrollment metadata
  - device registry and approval state
- Resolve bootstrap flow:
  - first device creates `VaultKey`
  - password-derived key wraps `VaultKey`
  - device keystore key also wraps `VaultKey`
  - second device must authenticate, then receive approval from an existing device before getting a usable wrapped key
- Resolve "last device lost" flow explicitly. Recommended plan note:
  - recovery codes can authorize re-wrapping `VaultKey` for a replacement device
  - a registered hardware security key can satisfy step-up recovery requirements
  - a second approved device remains the preferred recovery and approval mechanism whenever available
  - email can notify and assist account access recovery, but should not by itself decrypt or restore the vault
- Specify platform key storage:
  - Android Keystore with biometric-gated use where available
  - Web Crypto plus IndexedDB for the React app, ideally gated by WebAuthn/passkey before enabling persistent unwrap material
  - WebAuthn/FIDO2 support for hardware security keys on the web path and compatible platform flows
- Create individual test files (one test per file):
  - `tests/crypto/TestPasswordKdfParameters.cs`
  - `tests/crypto/TestVaultKeyWrapUnwrap.cs`
  - `tests/crypto/TestTotpSecretEncryptDecrypt.cs`
  - `tests/crypto/TestDeviceWrapRevocation.cs`
- Run tests to verify:
  - backend unit tests for wrapping/unwrapping and record serialization
  - client unit tests for local unlock and cache handling

### Phase 3: Backend architecture in C# .NET 10
- Create an ASP.NET Core solution structure such as:
  - `src/Server.Api/`
  - `src/Server.Application/`
  - `src/Server.Domain/`
  - `src/Server.Infrastructure/`
- Start with PostgreSQL as the only required backend datastore for the MVP.
- Implement password-derived verifier authentication so the raw password is never sent to the server.
- Define core entities:
  - `User`
  - `Device`
  - `VaultEntry`
  - `VaultKeyEnvelope`
  - `PendingDeviceApproval`
  - `AuditEvent`
  - `RecoveryChallenge`
- Implement APIs for:
  - register and sign in using the password-derived verifier flow
  - device registration
  - create approval request
  - approve or reject device
  - sync vault entries
  - fetch encrypted envelopes for the current device
  - generate, rotate, and redeem recovery codes
  - enroll and use hardware security keys for recovery step-up
  - initiate and complete account recovery notifications
  - list/revoke devices
- Store only ciphertext and envelopes, never plaintext TOTP secrets.
- Add optimistic concurrency or per-record versioning to sync endpoints.
- Add audit logging for:
  - login
  - failed login
  - device enrollment
  - device approval
  - recovery code generation and redemption
  - hardware security key enrollment and use
  - recovery start/completion
  - vault export/import if later added
- Add production protections:
  - IP and account-based rate limiting
  - short-lived approval tokens
  - signed nonce/challenge flows
  - email throttling
  - delayed recovery-material release with cancellation window
- Create individual test files (one test per file):
  - `tests/api/test_register_user.cs`
  - `tests/api/test_register_verify_email.cs`
  - `tests/api/test_register_device.cs`
  - `tests/api/test_request_device_approval.cs`
  - `tests/api/test_approve_device.cs`
  - `tests/api/test_sync_vault_entry.cs`
  - `tests/api/test_email_recovery_rate_limit.cs`
  - `tests/api/test_password_change_atomicity.cs`
  - `tests/api/test_refresh_token_rotation.cs`
  - `tests/api/test_recovery_material_pending_response.cs`
  - `tests/api/test_audit_log_written.cs`
- Run tests to verify:
  - `dotnet test`
  - endpoint integration tests against a test database

### Phase 4: React web client
- Create the React client first, with responsive design as a core requirement across desktop and mobile-sized layouts.
- Create modules for:
  - auth
  - encrypted local cache
  - vault list/details
  - code generation
  - device approval
  - audit log display
- Use Web Crypto for local operations and IndexedDB for cached encrypted data.
- Decide whether the browser stores unwrap material persistently or requires unlock each session. Favor stricter defaults for early releases.
- Implement TOTP generation locally in the browser after unlock; do not call the server to generate codes.
- Make WebAuthn mandatory for persisting browser device unwrap material; password-only web sessions stay ephemeral.
- Enforce the web lock policy with inactivity auto-lock, in-memory state clearing, and a visible "Lock now" action.
- Implement device approval and recovery UX consistent with the Android flow.
- Add recovery management UX for:
  - viewing recovery-code status and regenerating codes
  - registering a hardware security key through WebAuthn where supported
  - preferring an existing approved device for new-device bootstrap
- Define responsive layout requirements for:
  - narrow mobile viewport account lists
  - code tiles and countdown timers
  - device management and audit screens
  - enrollment and recovery flows without desktop-only assumptions
- Add camera-based QR enrollment on the web via `getUserMedia`.
- Add QR image upload on the web for screenshots or exported QR images.
- Add direct paste/import of `otpauth://` URIs on the web.
- Prefer `shadcn/ui` components styled with Tailwind and use Zustand for local UI state such as unlock state, active dialogs, and selected accounts.
- Add warning UX for browser risk boundaries, especially on shared machines.
- Create individual test files (one test per file):
  - `src/tests/AddVaultEntry.test.tsx`
  - `src/tests/UnlockVault.test.tsx`
  - `src/tests/GenerateTotpLocally.test.tsx`
  - `src/tests/PendingDeviceApproval.test.tsx`
  - `src/tests/AuditLogView.test.tsx`
  - `src/tests/ResponsiveVaultLayout.test.tsx`
  - `src/tests/WebQrEnrollment.test.tsx`
  - `src/tests/WebQrImageUpload.test.tsx`
  - `src/tests/OtpauthUriPaste.test.tsx`
  - `src/tests/OtpauthParserMissingFields.test.tsx`
  - `src/tests/OtpauthParserEncodedValues.test.tsx`
  - `src/tests/OtpauthParserNonstandardParams.test.tsx`
  - `src/tests/WebAutoLockAfterInactivity.test.tsx`
  - `src/tests/WebLockNowAction.test.tsx`
- Run tests to verify:
  - project test command for unit/component tests
  - browser-based checks for IndexedDB and Web Crypto integration
  - responsive behavior checks for common viewport sizes

### Phase 5: Android client
- Create Android app modules for:
  - authentication/session
  - vault crypto
  - sync
  - TOTP generation
  - device approval
- Support adding accounts manually by entering issuer, account name, and secret.
- Support QR enrollment data generation/display if the app must export to other authenticators later.
- Support image-based QR import and direct `otpauth://` paste if shared parsing utilities are used across clients.
- Validate shared `otpauth://` parsing against malformed URIs, URL-encoded values, and non-standard parameters before accepting an imported account.
- Cache encrypted vault entries locally and generate TOTP codes offline from decrypted secrets only after unlock.
- Integrate Android Keystore for wrapping the vault key and enforce the mobile app-lock policy before vault access.
- Implement new-device approval UX:
  - sign in with password
  - mark device as pending
  - wait for approval from an existing device
  - fetch device-wrapped vault key after approval
- Implement device management UI:
  - list approved devices
  - revoke device
  - generate and rotate recovery codes
  - show recent security events
- Create individual test files (one test per file):
  - `app/src/test/.../AddAccountManuallyTest.kt`
  - `app/src/test/.../GenerateTotpOfflineTest.kt`
  - `app/src/test/.../UnlockVaultWithBiometricTest.kt`
  - `app/src/test/.../PendingApprovalFlowTest.kt`
  - `app/src/test/.../OtpauthParserMissingFieldsTest.kt`
  - `app/src/test/.../OtpauthParserEncodedValuesTest.kt`
  - `app/src/test/.../OtpauthParserNonstandardParamsTest.kt`
  - `app/src/test/.../AutoLockAfterBackgroundTest.kt`
  - `app/src/test/.../RequireUnlockBeforeShowingCodesTest.kt`
- Run tests to verify:
  - Gradle unit tests
  - Android instrumentation tests for keystore/biometric behavior where feasible

### Phase 6: Recovery, hardening, and rollout
- Finalize the recovery policy. Strong recommendation:
  - separate account recovery from vault recovery
  - use second-device approval as the preferred bootstrap and recovery path
  - require recovery codes or a hardware security key for last-device recovery
  - keep email limited to notifications and account-level recovery assistance unless you intentionally accept a weaker vault-security model
- Implement recovery guardrails:
  - cooldown windows
  - out-of-band notifications to existing devices
  - audit alerts
  - recovery session risk scoring if available
  - one-time recovery code consumption and regeneration rules
  - hardware-key challenge verification and revocation handling
  - release hold for recovery material with explicit cancellation support
- Add operational monitoring:
  - suspicious login metrics
  - approval denial metrics
  - recovery attempt metrics
- Add backup/export policy only if explicitly desired later; avoid expanding MVP before core security is solid.
- Prepare deployment and secret-management guidance for backend encryption settings, email provider configuration, and database protection.
- Create individual test files (one test per file):
  - `tests/security/test_recovery_cooldown.cs`
  - `tests/security/test_existing_device_notified.cs`
  - `tests/security/test_revoked_device_cannot_sync.cs`
  - `tests/security/test_rate_limit_lockout.cs`
- Run tests to verify:
  - full backend suite
  - Android suite
  - React suite
  - manual end-to-end validation of first device, second device approval, revoke device, and no-device recovery scenario

## Distribution model: open core

PsTotp follows an **open-core model** with two repositories:

### Public repository (`pstotp`)
Everything in this repo is open source and free:
- **Server** — full ASP.NET Core API (all endpoints, all DB providers)
- **Web client** — full React app with server sync
- **Android standalone** — local-only TOTP authenticator (`:app` + `:core` modules)

### Private repository (`pstotp-sync`)
Paid add-on, not open source:
- **Android `:sync` module** — server sync implementation for Android
- **iOS sync module** (future)

### Repo structure
```
pstotp/                          # Public repo
├── src/                         # .NET server
├── client/web/                  # React web client (full sync)
└── client/android/              # Android app (standalone)
    ├── app/                     # :app module
    ├── core/                    # :core module (crypto, DB, TOTP)
    └── settings.gradle.kts      # Conditionally includes :sync

pstotp-sync/                     # Private repo
└── android/
    └── sync/                    # :sync module (API client, device pairing, vault sync)
```

### Integration mechanism
- `settings.gradle.kts` uses Gradle composite build (`includeBuild`) to include the `:sync` module when the sibling repo is present on disk
- `:core` defines a `SyncProvider` interface; `:sync` implements it
- `:app` discovers the implementation at runtime via reflection (`Class.forName`)
- When `:sync` is absent, the app runs in standalone mode — "Connect to Server" is hidden or shows "available in Pro"
- Single APK output either way; no build flavors needed

### Monetization enforcement
- Client-side feature gating is trivially bypassable — not relied upon
- **Server-side purchase validation** is the real gate:
  1. User purchases sync via Google Play / App Store
  2. App sends purchase token to PsTotp server
  3. Server validates token with Google/Apple receipt verification API
  4. Server marks account as paid
  5. All sync endpoints check paid status server-side
- Self-hosters who run their own server can use sync freely (they have the source) — this is acceptable because they were never going to pay

### What this means for the web client
The web client ships fully featured (with sync) in the public repo. It serves as:
- The reference implementation
- The free companion to a self-hosted server
- A demonstration of the sync protocol

The paid value is native mobile sync — the polished Android/iOS experience with offline queueing, biometric unlock, and background sync.

## Deployment as a system service

The server binary supports running as a console app, a Windows Service, a Linux systemd service, or a macOS launchd daemon from the same build — no conditional compilation or separate publish profiles needed.

### Publish

```bash
dotnet publish src/Server.Api/PsTotp.Server.Api.csproj -c Release -o ./publish
```

### Windows Service

```powershell
# Create (run as Administrator)
sc create PsTotp binPath="D:\path\to\publish\PsTotp.Server.Api.exe"
sc description PsTotp "PsTotp TOTP Authenticator Server"

# Start / stop
sc start PsTotp
sc stop PsTotp

# (Optional) Run under a specific account
sc config PsTotp obj="DOMAIN\user" password="pass"

# Remove
sc stop PsTotp
sc delete PsTotp
```

The service account needs write access to the data directory (`%APPDATA%\pstotp` for the default `LocalSystem` account, or overridden via `PSTOTP_DATA` / `DataDirectory`).

### Linux systemd

Create `/etc/systemd/system/pstotp.service`:

```ini
[Unit]
Description=PsTotp TOTP Authenticator Server
After=network.target

[Service]
Type=notify
ExecStart=/usr/bin/dotnet /opt/pstotp/PsTotp.Server.Api.dll
WorkingDirectory=/opt/pstotp
User=pstotp
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=PSTOTP_DATA=/var/lib/pstotp
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

`Type=notify` is required — `UseSystemd()` sends the sd_notify readiness signal so systemd knows the app has started.

```bash
# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable pstotp
sudo systemctl start pstotp

# Check status / logs
sudo systemctl status pstotp
sudo journalctl -u pstotp -f
```

### macOS launchd

Create `~/Library/LaunchAgents/com.pstotp.server.plist` (user agent) or `/Library/LaunchDaemons/com.pstotp.server.plist` (system daemon):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.pstotp.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/dotnet</string>
        <string>/opt/pstotp/PsTotp.Server.Api.dll</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/opt/pstotp</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>ASPNETCORE_ENVIRONMENT</key>
        <string>Production</string>
        <key>PSTOTP_DATA</key>
        <string>/var/lib/pstotp</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/pstotp/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/pstotp/stderr.log</string>
</dict>
</plist>
```

```bash
# Load and start
launchctl load ~/Library/LaunchAgents/com.pstotp.server.plist

# Stop and unload
launchctl unload ~/Library/LaunchAgents/com.pstotp.server.plist

# Check status
launchctl list | grep pstotp
```

No code changes are needed — launchd manages a regular process. There is no `UselaunchdService()` equivalent; the app runs as a console app and launchd handles lifecycle (restart, boot start).

### Notes

- Browser auto-open is automatically skipped when running as a Windows Service or systemd service. On macOS launchd, the `OpenBrowser` config key can be set to `false` to disable it.
- `UseWindowsService()` and `UseSystemd()` are no-ops when the app is not running under their respective service managers, so the same binary works everywhere.
- For production deployments behind a reverse proxy (nginx, Caddy), leave `EnableHttps=false` (default) and terminate TLS at the proxy.

## Implementation Status (as of 2026-04-19)

### Phases 1–4: Complete
All server and web client features are implemented:
- **Server API**: 14 endpoint classes + 3 helpers, minimal API pattern, `IExceptionHandler` with ProblemDetails
- **Dual auth**: httpOnly cookies for web, Bearer tokens for mobile, `OnMessageReceived` JWT extraction
- **Multi-DB**: PostgreSQL + SQL Server + MySQL + SQLite, separate migration assemblies, `DatabaseProvider` config key
- **Zero-config startup**: SQLite auto-default, JWT auto-gen, Fido2/CORS auto-config, rolling file logs, browser auto-open
- **Crypto login/register**: Client-side Argon2id, HKDF-SHA256, HMAC-SHA256 challenge-response, AES-256-GCM envelopes
- **Vault sync**: Client-side encryption with VaultKey (AES-256-GCM + AEAD with entry ID), PUT/DELETE sync, optimistic concurrency
- **WebAuthn/FIDO2**: Passkey registration, passwordless login with device envelope, recovery step-up
- **Device management**: Approval, rejection, revocation with ECDH P-256 key exchange, self-healing envelopes; list sorted server-side by `ApprovedAt` desc (pending last) with `RevokedAt` exposed for client bucketing
- **Recovery**: Recovery codes (Argon2id hashed), hold period, rate limiting, WebAuthn step-up, recovery seed
- **Admin tooling**: Config-based roles, user list/detail/disable/enable/delete, force password reset
- **Forgot password**: Email verification + device ECDH key for vault re-encryption
- **Email service**: SMTP via MailKit, graceful fallback to inline codes (`NullEmailService`)
- **Web client**: Full React 19 + TypeScript app — login (password + passkey), vault CRUD, list/grid layouts with manual/alpha/LRU/MFU sort (natural or reversed direction, snapshot-stable during use), QR scanning (camera + image + clipboard), countdown rings, service icons (70+), search, page transitions, configurable inactivity auto-lock (1min–never), audit log, device management, recovery management, admin panel, settings, backup/restore, import (own encrypted + plain + otpauth:// + Google Authenticator migration + Aegis + 2FAS), color themes
- **Session cleanup**: Background service for expired sessions, revoked entities, soft-deleted entries (30-day retention)
- **Self-signed HTTPS**: Opt-in for LAN testing
- **Reverse-proxy support**: `BasePath` + `UsePathBase` + `UseForwardedHeaders` + runtime `__PSTOTP_BASE__` substitution in `index.html` so the same bundle serves at root or under `/prefix`
- **Production error handling**: `ApiClient` translates JSON `detail`, status codes, and network failures into user-friendly messages — reverse-proxy HTML never reaches the UI; network errors during token refresh are re-thrown without killing the session
- **Tests**: 139 backend (MSTest — added device list sort + `RevokedAt` exposure), 107 web (Vitest — includes parity tests for all three external import formats)

### Phase 5 (Android): Complete
- **Kotlin + Jetpack Compose**, Material 3, Material You dynamic colors (Android 12+), `FLAG_SECURE` on the activity (screenshots/screen-capture blocked)
- **Crypto stack** matching web exactly: Argon2id (argon2kt), HKDF-SHA256, AES-256-GCM with AEAD, TOTP (SHA1/SHA256/SHA512, 6/8 digits)
- **Local encrypted vault**: Room/SQLite, password-derived key hierarchy, constant-time verifier comparison
- **Server sync (connected mode)**: Password-derived verifier login, ECDH P-256 device keys, pending→approved device flow with envelope receipt, full push/pull sync with offline queue and optimistic concurrency, JWT Bearer with auto-refresh (network failures during refresh don't kill the session), recovery flow with hold period + WebAuthn step-up, audit log viewer, recovery-code regeneration, password change
- **Biometric unlock**: Android Keystore-bound CryptoObject, per-install IV/ciphertext, Settings toggle, cached-IV self-heal on enable/disable cycling
- **WebAuthn/passkey login**: Credential Manager API (credentials 1.5.0 + play-services-auth 1.5.0); register, passwordless login with `NeedPassword` fallback, recovery step-up. Verified with YubiKey 5 NFC against production nginx
- **Screens**: Setup, Unlock (password + biometric + passkey), Vault (list + Authy-style grid with detail panel, per-entry countdown ring, search, drag-to-reorder, tap-anywhere-to-copy with clipboard-clear toast after 30s), Add Account (4 tabs: camera QR, image QR, manual, paste URI), Edit Account, Settings, Connect Server, Devices, Change Password, Audit Log, Regenerate Codes, Passkey Management, Recovery
- **Import**: `otpauth://` URIs, own `pstotp-plain` / `pstotp-export`, Google Authenticator `otpauth-migration://` (hand-rolled protobuf reader, no new dep), Aegis plain JSON, 2FAS JSON
- **Export**: encrypted JSON, plain JSON, otpauth URIs
- **Sort**: manual, alphabetical, recently used, most used — each with natural/reversed direction, snapshot-stable during use so tapping to copy doesn't reshuffle the list mid-interaction
- **Layout**: list view and Authy-style grid view toggle, with detail panel on top when in grid mode
- **Vault-key mismatch detection**: decrypt failures surface as loud `VaultKeyMismatchException` instead of silently producing an empty vault — closed a class of wrong-key bugs that had hit several auth paths
- **Service icons**: 50+ branded + custom colors; URL icons downloaded/resized at import (proxy with SSRF protection on the server side)
- **Auto-lock**: configurable timeout (1 min / 5 min / 15 min / 1 hour / Never) via `AppLifecycleObserver`
- **Navigation**: Jetpack Navigation Compose, 15 routes
- **Tests**: 69 unit tests in `:core` covering crypto, protobuf import readers, vault-key mismatch heuristic, `ApiClient.buildErrorMessage`
- **Module structure**: `:app` (UI + ViewModel) and `:core` (crypto, DB, repository, sync, models)

### Phase 6: Partial
- **Deployment story**: Dockerfile + docker-compose.yaml + `build.sh`/`build.ps1` with versioning; reverse-proxy walkthrough in DEPLOY.md; verified end-to-end behind nginx with a real TLS certificate at both root and `/prefix` deployments
- **Not started**: OAuth2 SMTP (XOAUTH2) for Outlook.com / Gmail without app passwords; iOS client; signed Android release build (keystore wiring, Play Store listing); documentation backlog (see `memory/future_work.md`)
