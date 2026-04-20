# PsTotp — Troubleshooting

Symptom-first lookup for operators running a PsTotp instance. Each
entry is **Symptom → Cause → Fix**. Grep-friendly — the symptoms try
to match the error text or log line you'd actually see.

For the happy-path setup that avoids most of these, start with
`docs/DEPLOY.md`. For daily operations, see `docs/ADMIN.md`.

## Server runtime

### Service won't start — "Jwt:Secret is required"

**Cause.** Production configuration doesn't set `Jwt:Secret` and the
server isn't in the zero-config SQLite mode that would auto-generate
one. The secret is only auto-created when `DatabaseProvider` is unset
and no connection string is provided.

**Fix.** Set `Jwt:Secret` to a base64-encoded 256-bit key. Generate one
with `openssl rand -base64 32` (Linux/macOS) or
`[Convert]::ToBase64String([byte[]](1..32 | % {Get-Random -Max 256}))`
(PowerShell). See `docs/DEPLOY.md` → *Configuration and secrets*.

### Startup fails with "connection refused" on Postgres/MySQL/SQL Server

**Cause.** Database isn't reachable from the app. In docker-compose
this usually means the `db` service hasn't passed its healthcheck yet
and the `app` container started anyway; on systemd it means the DB
service isn't up or the connection string points somewhere wrong.

**Fix.** Check the DB service is running and accepting connections
(`pg_isready -h <host>`). In compose, `depends_on: condition:
service_healthy` is already set — if you removed it, put it back.
If the connection string looks right but still fails, check network
reachability from inside the app container / service user:
`docker compose exec app ...` or `sudo -u pstotp ...`.

### Requests to /api/* return 200 with HTML instead of JSON

**Cause.** `BasePath` is set, but ASP.NET's auto-inserted `UseRouting`
ran **before** `UsePathBase`. Routing then matches against the raw
`/prefix/...` path, nothing matches, and the SPA fallback catches
every request — returning `index.html` as a 200.

**Fix.** Make sure `Program.cs` calls `app.UsePathBase(basePath)`
followed by an explicit `app.UseRouting()`. The shipped code already
does this; only a fork that reordered the pipeline would hit this.

### SPA loads but `__BASE_PATH__` placeholder is visible in the HTML

**Cause.** Something is serving `wwwroot/index.html` raw, bypassing
the MapFallback handler that substitutes the placeholder at serve
time. The shipped pipeline uses `UseStaticFiles` without
`UseDefaultFiles`, so the fallback always gets `/` — only a fork that
re-added `UseDefaultFiles` (or otherwise intercepts the root path)
would hit this.

**Fix.** Remove whatever is serving `index.html` ahead of the
MapFallback handler. Keep `UseStaticFiles` (it serves everything else
in `wwwroot`); let the SPA fallback handle `/` so it can substitute
`window.__PSTOTP_BASE__`.

### Login succeeds in browser but API calls get CORS errors

**Cause.** `AllowedOrigins` doesn't include the origin the browser
actually presents.

**Fix.** Set `AllowedOrigins` to the exact origin including scheme
(e.g. `https://totp.example.com`, not `totp.example.com`). Multiple
origins are semicolon-separated. In dev,
`appsettings.Development.json` already allows `http://localhost:5173`.

### "The specified request headers are not allowed" after moving hostnames

**Cause.** `Fido2:Origins` is stale — browsers and Credential Manager
compare the origin the ceremony was initiated on against this list.
Any mismatch, including `http` vs `https` or `example.com` vs
`totp.example.com`, rejects the ceremony.

**Fix.** Update both `Fido2:ServerDomain` (the RP ID, which is the
bare hostname — no scheme, no port) and `Fido2:Origins` (full
origins, with scheme). Existing passkeys remain usable **only** while
the RP ID is unchanged; changing `Fido2:ServerDomain` invalidates all
registered credentials.

### Reverse proxy serves with `/prefix` stripped

**Cause.** `proxy_pass http://backend/;` with the trailing slash. This
tells nginx to strip the `location` prefix before forwarding, which
breaks `UsePathBase`.

**Fix.** `proxy_pass http://backend;` — no trailing slash. See the
nginx walkthrough in `docs/DEPLOY.md`.

### HTTPS-aware redirects loop or send the user to http://

**Cause.** `X-Forwarded-Proto` isn't being trusted. Either the proxy
isn't setting it, or `ReverseProxy:KnownProxies` doesn't include the
proxy's IP.

**Fix.** Ensure the proxy sets `X-Forwarded-Proto $scheme`. Add the
proxy's IP (or range) to `ReverseProxy:KnownProxies`. Loopback is
allowed by default — if your proxy isn't on loopback, you must list it.

### "Address already in use" on port 5000

**Cause.** Another PsTotp instance, another ASP.NET app, or something
unrelated has port 5000.

**Fix.** Stop the other process, or set `ASPNETCORE_URLS` to a
different port: `ASPNETCORE_URLS=http://0.0.0.0:5005`.

### Migrations weren't applied after upgrade (non-SQLite)

**Cause.** Production migrations don't auto-apply for non-SQLite
providers by default. If you skipped the migrate step after updating
the binary, startup succeeds but any new-schema queries fail with
column/table errors.

**Fix.** Run the new binary with `--migrate` once, then start the
service normally:

```bash
PsTotp.Server.Api --migrate
# then start the service as usual
```

Or, for single-instance hobbyist deployments, opt into boot-time
migration via `Database:ApplyMigrationsOnStartup=true`. See
`docs/DEPLOY.md` → *Upgrade / migration workflow* for tradeoffs.

## Login

### User reports "Incorrect password" but swears the password is right

**Cause.** Several possibilities, ordered by likelihood:

- They're typing a different password than the one stored (happens more
  than you'd think — they had multiple).
- Their account has `ForcePasswordReset=true` and the client is
  routing them into reset flow which they abandoned.
- They're rate-limited (5 failed attempts in 15 minutes returns HTTP
  429) and every subsequent attempt silently 429s.
- Server clock is drifting relative to the user's device and the JWT
  issued at login is immediately considered expired.

**Fix.** Check the audit log for `login_failed` (wrong password)
vs a 429 pattern. If they're rate-limited, tell them to wait 15
minutes or restart the server (the limiter is in-memory). If `ForcePasswordReset`
is set unexpectedly, clear it via the admin UI. If server clock is off,
`sudo timedatectl status` / Windows Time service.

### 429 Too Many Requests on /api/auth/login

**Cause.** Rate limiter hit: 5 failures per email per 15 minutes.

**Fix.** Wait it out or restart the server (the in-memory limiter
resets on restart). There's no admin "reset for this user" lever.

### Stuck in "please set a new password" loop after password reset

**Cause.** `ForcePasswordReset` didn't clear. Either the reset flow
was abandoned mid-way, or the flag was manually set without a
matching user-initiated reset.

**Fix.** In the admin UI, open the user's detail panel — there's no
explicit "clear force reset" button because a successful reset clears
it automatically. Easiest path: guide the user through
**Forgot password** from the login screen (email + new password).

### Android passkey: "No passkeys available" / "No credentials"

**Cause.** Credential Manager couldn't match any stored credential to
the RP ID. Usually:

- `assetlinks.json` isn't reachable at the **apex** domain (it has to
  be at `https://example.com/.well-known/assetlinks.json`, not under
  the `BasePath` prefix).
- The `Android.CertFingerprints` on the server doesn't match the
  signing certificate of the installed APK (debug cert differs from
  release cert).
- The RP ID doesn't match (user registered the passkey against a
  different hostname before you migrated).

**Fix.**

- Confirm `curl https://<apex>/.well-known/assetlinks.json` returns
  the expected JSON with your SHA-256 cert fingerprints.
- Confirm the fingerprint in config matches `keytool -printcert
  -jarfile <apk>` (or `gradlew signingReport`).
- If you changed RP IDs, users have to register fresh passkeys.

### Web passkey: "The operation either timed out or was not allowed"

**Cause.** Usually RP-ID / origin mismatch between browser and server,
or the user cancelled the Credential Manager / Windows Hello prompt.

**Fix.** Check `Fido2:ServerDomain` equals the bare hostname in the
browser URL, and `Fido2:Origins` contains the full origin. If it's
a user cancellation, their next attempt should work; a repeat
failure on a fresh attempt points at config.

### Tokens accepted in one browser tab, rejected in another

**Cause.** `__Host-` cookies are scoped strictly — they require
`Secure`, no `Domain=`, and `Path=/`. If one tab is at the origin root
and another is at a subpath served by a different app, cookies from
one won't reach the other.

**Fix.** Both tabs need to be at the PsTotp origin. If you're serving
multiple apps under one domain, use separate hostnames
(`totp.example.com`, not `example.com/totp` when both apps set
`__Host-` cookies).

## Vault

### "Vault key mismatch: N of M entries could not be decrypted"

**Cause.** The vault key in memory doesn't match the key that encrypted
the stored entries. Common triggers:

- Admin-restored a backup from a different server, and the user's
  device still has the old vault key cached.
- User's device envelope was rewritten (password change on another
  device, recovery) and this device's copy is stale.
- Actual key mismatch after a multi-device re-key where one device
  didn't sync.

**Fix.** On the affected device: lock the vault and unlock again to
force a fresh key fetch (password login, or passkey). If the error
persists, the device is out of sync; sign out fully and sign back in.
If it happens to *every* device at once, check that you restored a
matching backup — server data and device-wrapped keys need to be from
the same snapshot.

### Vault appears empty after sync even though entries exist on another device

**Cause.** Historically this was a silent-drop bug (wrong-key entries
were silently filtered out and the vault appeared empty). Current code
throws `VaultKeyMismatchException` instead — if you're not seeing that
error, something else is going on.

**Fix.** Check the entries exist on the server side (admin-list the
user's vault count — the user detail panel shows it). If the count
looks right, check sync status / network. If the count is zero too,
the issue is upstream of sync — maybe a deletion that's propagated.

### Sync fails with HTTP 409 Conflict repeatedly

**Cause.** Optimistic-concurrency collision: the server has a newer
`entryVersion` than the client is trying to push. The client should
pull-then-retry.

**Fix.** Trigger a **Sync Now** in Settings → Server Sync (web:
Settings → Account panel has a similar control). If conflicts persist,
the client's local state has diverged — lock and re-unlock to re-pull
from the server as the source of truth.

### Drag-to-reorder doesn't persist

**Cause.** Drag is only active in **Manual** sort mode. In any other
mode the drag handle is hidden, and if you forced it visible somehow,
the reorder wouldn't apply.

**Fix.** Switch sort mode to **Manual** (sort menu in the top bar),
then rearrange.

## Android

### Biometric unlock fails with "Biometric unlock failed: null"

**Cause.** Historical bug: cached IV went stale after biometric was
disabled and re-enabled, so the decrypt cipher was built with the old
IV. Fixed in recent builds — the ViewModel now refreshes the cached
IV in `completeBiometricEnrollment` and clears it in `disableBiometric`.

**Fix.** Update the client. If reproduction persists on a current
build, disable biometric in Settings, lock the vault, re-enable it —
that forces a fresh enrollment.

### App launches but every server call fails with "Could not reach the server"

**Cause.** Typed server URL is wrong, server is actually down, or the
device is offline. The message wraps `ConnectException` /
`UnknownHostException` into a friendly string.

**Fix.** Tap **Sync Now** in Settings → Server Sync — the error
message there shows the specific cause ("Server not found. Check the
URL" vs "Could not reach the server" vs "Secure connection failed").
Common gotcha: the server URL in the Android app is expected to
include `/api` (e.g. `https://host/totp/api`), because the client
appends endpoint paths to that base.

### Tokens stay revoked after switching networks / airplane mode

**Cause.** If an access token expires mid-flight and the refresh call
fails because the network is out, the client is meant to preserve the
session and let the user retry. A `NetworkException` during refresh
is specifically re-thrown without clearing tokens.

**Fix.** Wait for the network to come back, then re-trigger whatever
you were doing. If the session really is invalidated (server-side
logout or session expiry), you'll be routed to the login screen with
"Session expired — please reconnect".

### `FLAG_SECURE` blocks legitimate screen sharing

**Cause.** Not a bug — `FLAG_SECURE` is set on the main activity
unconditionally to prevent screenshots, screen recorders, and
screen-share tools from capturing your vault. This is deliberate
authenticator hygiene.

**Fix.** None. If you need to demonstrate the app on a video call,
describe it or use a separate screen-capture mode in the OS that
explicitly bypasses `FLAG_SECURE` (most don't).

## Web

### Session disappears on browser restart

**Cause.** JWT access token lives in an httpOnly cookie, refresh token
in another. Both are session cookies (no explicit Max-Age), so they
go away when the browser closes. This is intentional — it keeps a
locked vault locked.

**Fix.** Nothing to fix. Sign in again.

### "Failed to fetch" after server was briefly down

**Cause.** Native `fetch()` throws `TypeError("Failed to fetch")` on
network failure. The client wraps this into a friendlier `NetworkError`
("Could not reach the server") for display, and does **not** log the
user out on refresh failures — see `docs/architecture/PLAN.md` for
the rationale.

**Fix.** If the user is shown "Could not reach the server", wait for
the server to come back and retry. The session isn't invalidated by
the network blip.

### Device-key-store unavailable / IndexedDB blocked

**Cause.** User is in private browsing (IndexedDB is either ephemeral
or disabled depending on the browser) or has disabled cross-site
storage in a way that affects the PsTotp origin.

**Fix.** Use a normal browser profile. PsTotp needs IndexedDB for the
device ECDH private key; without it, passkey-driven login can't
rebuild envelopes.

### TOTP codes are consistently wrong by one interval

**Cause.** Device clock is drifting.

**Fix.** Enable system-level time sync on the device displaying the
codes. TOTP is clock-based — PsTotp doesn't apply a drift correction
window beyond what RFC 6238 specifies.

## Recovery

### User panics that recovery is taking "24 hours"

**Cause.** The hold period is deliberate: after redeeming a recovery
code, material isn't released until a configurable delay elapses
(`Recovery:HoldPeriodHours`, default 24). This gives a legitimate
owner time to notice a hostile recovery attempt.

**Fix.** Explain that it's by design. If you need to shorten it for
a trusted user (e.g. locked-out admin), change the config and
restart. Don't set it to zero in anything resembling production —
you'd lose the defence-in-depth against stolen recovery codes.

### Recovery session expired mid-flow

**Cause.** The session has a finite `ExpiresAt` and the user took too
long between steps.

**Fix.** Start recovery over. The rate limit is 3 recovery attempts
per email per hour, so they may need to wait.

### Recovery code rejected

**Cause.** Either the code is wrong (typo, transposed digits, wrong
slot), or the code was already used, or the rate limit hit.

**Fix.** Double-check the code. Audit the `recovery_code_failed` vs
`recovery_code_redeemed` events — if a redeemed event happened for the
same code, it was used successfully on a different attempt. If 3
failures already happened in the hour, wait it out.

### After recovery, other devices can't decrypt the vault

**Cause.** Recovery completes by wrapping the vault key with a fresh
device envelope for the new device. Other devices still have their
**old** envelopes, which were wrapped with the key present at their
last login. If the recovery flow re-keyed the vault (some paths do),
those envelopes no longer work.

**Fix.** Other devices need to sign in again (password login
re-derives their envelope). If they refuse, revoke them via the
admin UI and let the user re-approve from the recovered device.

## Common HTTP responses

### 403 Forbidden from /api/admin/*

**Cause.** The caller's JWT doesn't carry the `Admin` role claim. This
happens when a non-admin unhides the Admin tab in DevTools and tries
to use the buttons; it also happens when someone is removed from the
`Admins` config but still holds a pre-removal token.

**Fix.** If the user is supposed to be admin, verify their email is
in the `Admins` array (remember: `Admins__0` syntax when passed via
environment variables), then have them sign out and back in. Role is
stamped at login time.

### 429 Too Many Requests

**Cause.** One of two limiters: login (5/15min) or recovery start
(3/hour).

**Fix.** Wait, or restart the server to reset the in-memory counters.

### 404 from /.well-known/assetlinks.json

**Cause.** Reverse proxy doesn't have a matching location for it, or
proxies it under the wrong prefix.

**Fix.** Add a top-level `location = /.well-known/assetlinks.json`
that forwards to `http://<kestrel>/.well-known/assetlinks.json`. See
`docs/DEPLOY.md` → *nginx* → at-prefix example.
