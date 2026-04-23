# PsTotp — API Guide

This document is the **narrative reference** for the PsTotp HTTP API —
how the flows fit together, what order callers invoke things in, and
what the zero-knowledge boundary means for your requests. The
field-level schema lives in [`docs/openapi.json`](openapi.json)
(generated from the server's endpoint metadata at build time). Drop
that file into [Redoc](https://redocly.github.io/redoc/) or the Scalar
UI served at `/scalar/v1` on a running instance for an interactive
explorer.

If you're writing a client (CLI, alt mobile app, integration script),
read this first, then generate types off the OpenAPI schema.

## Orientation

- **Base URL**: whatever host you deploy to (e.g. `https://totp.example.com`).
- **Reverse-proxy prefix**: every endpoint path in this doc is relative
  to the deployment's base path. If PsTotp is mounted under `/totp`,
  read `/api/vault` as `/totp/api/vault`.
- **API prefix**: everything non-static lives under `/api/…`.
- **OpenAPI**: `GET /openapi/v1.json` (always), `GET /scalar/v1`
  (Development only).
- **Health**: `GET /api/health` → `{ "status": "healthy" }`. Public,
  unauthenticated, useful for liveness probes.

## Authentication model

**Two transport styles, one token format.** Clients present a JWT
access token on every authenticated request. How the token is carried
is negotiated at login:

- **Web (`ClientType: "web"`)** → httpOnly `access_token` and
  `refresh_token` cookies. The server sets them on login; the browser
  sends them automatically. Clients include `credentials: "include"`
  on `fetch`.
- **Mobile (`ClientType: "android"` / `"ios"`)** → `accessToken` and
  `refreshToken` are returned in the JSON body. Clients store them
  (on Android via `EncryptedSharedPreferences`) and send
  `Authorization: Bearer <access-token>` on subsequent requests.

All authenticated requests also pass through an origin check and an
account-status check, so a revoked user or a foreign origin gets
rejected before the endpoint handler runs.

### Register

```
POST /api/auth/register/begin          → { registrationSessionId, emailVerificationRequired, verificationCode? }
POST /api/auth/register/verify-email   (only when emailVerificationRequired is true)
POST /api/auth/register                → user + initial device, logs in
```

First account created on a fresh install is an admin automatically
(first-user-wins); everything after goes through email verification if
`EmailVerificationRequired` is configured. Registration wraps the
vault key with the password-derived KEK and the device's ECDH public
key at the same time so the user is usable immediately after.

### Login (two-phase challenge-response)

Raw passwords never leave the client. Login is a HMAC-over-server-nonce
proof.

```
POST /api/auth/login                   request:  { email, device: { deviceName, platform, clientType, devicePublicKey? } }
                                       response: { loginSessionId, challenge: { nonce, kdf: { algorithm, memoryKb, iterations, parallelism, salt } } }

POST /api/auth/login/complete          request:  { loginSessionId, proof (HMAC), clientProofV2? }
                                       response: one of the shapes below
```

The client derives the password KEK from `password + salt` using
Argon2id with the returned KDF parameters, then HMACs the challenge
nonce with the KEK to produce `proof`. The server re-runs the same
HMAC against its stored verifier and compares.

**Complete's response shape depends on the device's state:**

- **Device approved, or first device** → access + refresh tokens
  (cookies for web, body fields for mobile), `envelopes` block with
  the password-wrapped vault key and — when `devicePublicKey` is
  provided — the device-wrapped vault key. Client decrypts whichever
  it can use and is now unlocked.
- **Device pending approval** → no tokens yet. Response includes
  `approvalRequestId` and the client should poll / surface a
  "waiting for approval" UI. An already-approved device on the same
  account must approve via `POST /api/devices/{deviceId}/approve`.

### Token refresh and logout

```
POST /api/auth/refresh                 rotate access token + refresh token
POST /api/auth/logout                  clear cookies / invalidate refresh token
```

Web clients get a 401 and silently refresh once before surfacing an
error — see the **Error model** section for the exact pattern.

### WebAuthn step-up

Passkeys are supported on web and Android. The two endpoint pairs
below cover both login and step-up (password-reset confirmation,
recovery-material release):

```
POST /api/webauthn/assert/begin        → { challenge, allowedCredentials, ... }
POST /api/webauthn/assert/complete     → proof of possession (scopes: login or recovery-stepup)
```

Registration (enrolling a new credential) is authenticated and uses
`/api/webauthn/register/{begin,complete}` under the user group.

### Password reset and recovery

Two distinct flows, often confused:

- **Password reset** (user remembers everything else, just wants a new
  password). Email-based verification, one-time code, then a
  password-change ceremony that rewraps the vault key.
- **Recovery** (user has lost all devices). Redeems a one-time
  recovery code, optionally does a WebAuthn step-up, then after a
  configurable **release hold window** receives the recovery envelope
  that can unwrap the vault key. The hold is defence-in-depth against
  stolen recovery codes.

```
Password reset:
  POST /api/auth/password/reset/begin      (email)
  POST /api/auth/password/reset/verify     (code)
  POST /api/auth/password/reset/complete   (new verifier + rewrapped envelopes)

Recovery:
  POST /api/recovery/codes/redeem          (email + code)
  POST /api/recovery/session/{id}/material (fetches recovery envelope once the hold has elapsed)
  POST /api/recovery/session/{id}/complete (rotates recovery codes, installs new device envelope)
```

See `docs/RECOVERY.md` for the operator-facing view and
`docs/architecture/key-hierarchy.md` for the crypto.

## Vault sync

The vault is the server's reason to exist. Every entry is AES-GCM
ciphertext keyed to the user's vault key — the server stores
`entryPayload` opaquely and never sees issuer, account, or secret.

```
GET    /api/vault                       → { entries: [...], serverTime }
PUT    /api/vault/{entryId}             upsert with optimistic concurrency
DELETE /api/vault/{entryId}             soft-delete (tombstone with deletedAt)
POST   /api/vault/reorder               batch sort-order update
```

### Entry shape on the wire

```json
{
  "id": "uuid",
  "entryPayload": "<base64 ciphertext>",
  "entryVersion": 7,
  "deletedAt": null,
  "updatedAt": "2026-04-22T12:34:56Z",
  "sortOrder": 3
}
```

Only opaque fields. If you think you need to add a plaintext field
here — `issuer`, `lastUsed`, anything — stop and re-read
`docs/architecture/threat-model.md`. Per-user metadata that the server
does see (device list, audit events, sort order, recovery timers)
lives elsewhere and is deliberately scoped to things the server
operates on.

### Optimistic concurrency on upsert

Every `PUT /api/vault/{entryId}` carries an `entryVersion` the client
believes it's updating. If the server's stored version doesn't match,
you get a 409:

```
409 Conflict
{ "Error": "Version conflict", "CurrentVersion": 9 }
```

Last-write-wins per project policy: clients refetch the entry, merge
their local change onto the server's state, and PUT again with the
new version. The `currentVersion` field tells you what to refetch
against.

### Icon library

Per-user blob of reusable icons. Same client-side encryption story as
vault entries; the server stores one row per user and enforces
optimistic concurrency both in-memory AND at the DB level
(`Version` is an EF concurrency token, so two racing writers that
both passed the in-memory check still get one 409 from the UPDATE):

```
GET /api/vault/icon-library             → { encryptedPayload, version, updatedAt }
PUT /api/vault/icon-library             request: { encryptedPayload, expectedVersion }
                                        409 shape: { Error, Version }
```

Payload cap is 2 MB. Clients cap to 100 icons client-side.

## Common sequences

### Sign in, unlock, sync

```
POST /api/auth/login                         → challenge
POST /api/auth/login/complete                → tokens + envelopes (or approval-pending)
# Client decrypts password-envelope + device-envelope locally → vault key
GET  /api/vault                              → ciphertext entries
# Client decrypts each entry locally
GET  /api/vault/icon-library                 → ciphertext library (optional)
```

### Add an entry

```
# Client generates the entry plaintext, encrypts with the vault key
PUT  /api/vault/{newUuid}                    body: { entryPayload, entryVersion: 1, sortOrder }
                                             200: { id, entryVersion: 1, updatedAt }
```

### Resolve a 409 on save

```
PUT  /api/vault/{id}                         body: { entryPayload, entryVersion: 7 }
                                             409: { Error, CurrentVersion: 9 }
GET  /api/vault                              → refetch
# Client re-encrypts the entry against the fresh server state
PUT  /api/vault/{id}                         body: { entryPayload, entryVersion: 9 }
                                             200
```

Same recipe for `/api/vault/icon-library` — read `version`, PUT with
`expectedVersion`, on 409 refetch + retry once.

### Handle a 401 mid-session

Access tokens are short-lived. On any authenticated request:

1. Server responds `401 Unauthorized`.
2. Client `POST /api/auth/refresh` (cookies / refresh token body).
3. On success: retry the original request once.
4. On refresh failure: log out and surface "session expired".

The web client's `api-client.ts` and the Android `ApiClient` both
implement this transparently with single-flight coalescing so
concurrent requests share one refresh.

## Error model

**Non-2xx responses return `{ "Error": "..." }`** on most paths, with
optional extra fields (`CurrentVersion`, `Version`, `RetryAfterSeconds`).
Callers should:

1. Check **status code** first — never branch on error-message text.
2. Parse the body as JSON best-effort; treat missing / malformed bodies
   as a plain status-coded error ("HTTP 500", etc.).
3. Never surface raw body text to users — a reverse proxy's HTML
   error page can otherwise end up in your UI. Both bundled clients
   (`client/web/src/lib/api-client.ts`,
   `client/android/core/src/main/java/.../core/api/ApiClient.kt`) follow
   this pattern; copy it.

Common statuses you'll see:

| Status | Meaning                              | Recipe                              |
| :----: | :----------------------------------- | :---------------------------------- |
| 400    | Validation / shape error             | Fix the request, surface `Error`    |
| 401    | Missing or expired access token      | Refresh + retry once                |
| 403    | Authenticated but forbidden          | Surface; don't retry                |
| 404    | Unknown entity / route               | Surface                             |
| 409    | Optimistic-concurrency mismatch      | Refetch + retry once (LWW)          |
| 429    | Rate limit                           | Back off per `RetryAfterSeconds`    |
| 5xx    | Server-side problem                  | Exponential backoff, surface error  |

## Admin endpoints

Require the `AdminPolicy` (role claim = admin). Not meant for
unattended scripts yet — the server issues access tokens via the
interactive password flow, and there's no machine-auth story today.
Operators who need scriptable admin access should use system-level DB
backups / dumps instead, or wait for the planned API-key mechanism.

```
GET    /api/admin/users
GET    /api/admin/users/{id}
POST   /api/admin/users/{id}/disable
POST   /api/admin/users/{id}/enable
POST   /api/admin/users/{id}/force-password-reset
DELETE /api/admin/users/{id}
POST   /api/admin/users/{id}/recovery-sessions/{sessionId}/cancel
POST   /api/admin/backup                     → application/json, password-encrypted export
POST   /api/admin/restore                    multipart; restores users + vaults + icon libraries
```

The backup format is DB-independent — export from a Postgres instance,
restore into SQLite, or vice versa. Both `/backup` and `/restore` ask
for a password so the file can leave the server's trust boundary
safely; see `docs/DEPLOY.md` for the operational walkthrough.

## Zero-knowledge boundary

A compact restatement of what the server does and does not see,
because it drives every design decision above:

- **Server sees**: email, device list + ECDH public keys, sort orders,
  audit events, timers (recovery hold, session TTLs), ciphertext
  blobs, wrapped envelopes.
- **Server never sees**: passwords (only the Argon2-derived verifier),
  vault keys (only wrapped forms), vault entry contents (only
  ciphertext), icon library contents (only ciphertext).

If you propose a feature that needs server-side plaintext access to
any vault material — cross-device search, "find duplicates",
server-computed stats — stop and reread
[`docs/architecture/threat-model.md`](architecture/threat-model.md)
first. That's the highest-value invariant in the whole system.

## Keeping this doc honest

The OpenAPI schema (`docs/openapi.json`) is the authoritative field
reference; `build.sh` / `build.ps1` regenerate it during a release
build and fail if the committed copy drifts. This narrative doc is
prose and drifts the old-fashioned way — send a PR if you spot
something stale.
