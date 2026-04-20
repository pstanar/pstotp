# PsTotp — Admin Guide

This guide is for people running a PsTotp instance for their own users:
daily operations, account management, audit log review, and routine
maintenance. It assumes the service is already deployed — `docs/DEPLOY.md`
covers that — and focuses on what you do afterwards.

For development workflow, see `docs/DEVELOPER.md`. For the design of the
crypto and sync model, see `docs/architecture/PLAN.md`. For symptoms /
error-message lookups, see `docs/TROUBLESHOOTING.md`.

## Becoming an admin

Admin is a role attached to user accounts, set via configuration:

```json
{
  "Admins": [ "you@example.com" ]
}
```

Add the email addresses of every admin to this array. The role is
applied to a user record **on login**, not on each request: if someone
is added to the list while they are signed in, they won't see the admin
UI until they sign out and back in.

There is no "first run" bootstrap flow — you make yourself admin by
putting your own email in the config before (or after) registering the
account. For the full config-override options across docker-compose,
systemd, and Windows Service deployments, see the
**Configuration and secrets** section of `docs/DEPLOY.md`.

## Reaching the admin UI

All admin tools live on the web client, not on Android. Sign in as an
admin → **Settings → Admin** tab. The tab is hidden entirely for
non-admin accounts.

**Note on hiding vs authorising.** Hiding the tab is a UX affordance,
not a security boundary. Every admin endpoint is mapped under a route
group with `.RequireAuthorization(AdminPolicy)`, where `AdminPolicy` is
`RequireRole("Admin")`. The role claim is stamped into the JWT by the
server at login from the `Admins` config array — the client can't forge
it, and removing a user from `Admins` means their next-issued token
won't carry the role. A non-admin who unhides the Admin tab in DevTools
can see the components, but every action they trigger returns 403 from
the server without running the handler.

Three things live on that page:

1. **User list** — with search, per-user detail expansion, and actions.
2. **Backup panel** — at the bottom of the page; see
   `docs/DEPLOY.md` → *Backup and restore* → *Admin DB backup* for the
   full story.
3. **Recovery-session widget** (inside each user's detail expansion,
   when applicable).

## User management

The user list shows every account with:

- status dot (green = active, red = disabled)
- badges for `ADMIN`, `DISABLED`, and `RESET` (force-password-reset flag)
- entry count, device count, passkey count, last-login date

Search box at the top filters by email (debounced 300 ms). Click a user
to expand their detail panel, which exposes the actions below.

### Disable / enable

`Disable` flips `User.DisabledAt` to the current timestamp. The server
revokes the user's JWT access tokens **immediately** via the
`token-version` claim check, so they're signed out of everything within
seconds — even if they have a live vault open. Refresh tokens are also
refused while the user is disabled.

When you `Enable` again, `DisabledAt` clears and the user can log in on
their next attempt (they still need a fresh password login; the old
tokens stay revoked).

Use disable when you want to suspend an account without destroying its
data — e.g. while you investigate suspicious activity. Use it in preference
to delete if you're not absolutely sure.

### Force password reset

Sets `User.ForcePasswordReset`. On the user's next login the client
routes them into the password-reset flow before they reach their vault.
The reset itself goes through the normal email-verified + device-key
rewrap path; you don't need to be involved after flipping the flag.

Use this after a credential-compromise suspicion, or when you've just
restored from a backup and want everyone to rotate their passwords.

### Delete user

Hard-deletes the user and every associated record:

- devices
- vault entries + key envelopes
- recovery codes + recovery sessions
- WebAuthn credentials
- audit events
- active login / registration / password-reset / refresh sessions

**This is irreversible.** No soft-delete, no tombstone. The only recovery
path after a mistaken delete is restoring an admin backup from before
the deletion. The UI requires an explicit confirmation.

### Cancel a recovery session

Recovery sessions are visible inside the user's detail panel when
there's an active one. Each session shows its status (`Pending`,
`Ready`, …), its earliest-release timestamp, and its expiry. A `Cancel`
button terminates it immediately.

You'd cancel a session when:

- The user started a recovery by mistake and wants to keep their
  existing credentials.
- You've seen suspicious activity and want to make sure a stray
  recovery attempt doesn't complete before you investigate.
- A session is stuck and you want to let the user re-initiate cleanly.

See `Recovery sessions` below for the wider lifecycle.

## Audit log review

Every state-changing action that matters is logged to `AuditEvents`
with the acting user, device, IP address, and a per-event JSON payload.

Events you'll see (from `src/Server.Api/AuditEvents.cs`):

- **Auth**: `login_success`, `login_failed`, `account_created`,
  `password_changed`, `password_reset_requested`, `password_reset_completed`
- **Devices**: `device_approved`, `device_rejected`, `device_revoked`
- **Recovery**: `recovery_code_failed`, `recovery_code_redeemed`,
  `recovery_material_released`, `recovery_completed`,
  `recovery_codes_regenerated`, `recovery_session_cancelled`
- **Admin**: `user_disabled`, `user_enabled`, `user_deleted`,
  `force_password_reset_set`
- **Backup**: `backup_exported`, `backup_restored`
- **Vault**: `vault_exported`, `vault_imported`
- **WebAuthn**: `webauthn_credential_registered`,
  `webauthn_assertion_verified`, `webauthn_credential_revoked`
- **System**: `system_shutdown`

Where to read them:

- **Each user's own events** are visible to that user in the web client
  under Settings → Audit. Good for user self-service and for giving a
  support-requester the exact event types you want them to look at.
- **Server logs** capture the same events as structured log entries (see
  `{DataDirectory}/logs/pstotp-*.log`; retention is 30 days). Useful
  when you want to correlate across users or grep for a specific IP.
- **The database** is the authoritative copy. Audit events participate
  in the endpoint's `SaveChangesAsync` unit-of-work, so if the action
  committed, the event committed. No "partial-commit" states to worry
  about.

Retention is currently unlimited in the DB — the `SessionCleanupService`
does **not** prune audit events. If your audit table is growing
uncomfortably, that's an operational decision (e.g., a scheduled
`DELETE FROM audit_events WHERE created_at < NOW() - interval '1 year'`
in your DB) that isn't automated.

## Backup and restore

See `docs/DEPLOY.md` → *Backup and restore*. The full story lives there;
the short version for an admin's routine:

- **Before any non-trivial change** (upgrade, DB move, mass user
  action): export an admin backup.
- Keep a rolling history of exports rather than overwriting a single
  file — the format is versioned and an older backup can't be re-generated
  after the fact.
- The backup password and the backup file together are equivalent to
  DB credentials. Store them accordingly.

Headless / scripted backup is **not supported today** — login is a
password-derived verifier flow, so there's no `curl`-friendly
authentication path. Use the UI. (Machine-auth for admin endpoints is
tracked in `memory/future_work.md`.)

## Session and token lifecycle

PsTotp tracks several distinct session types. Knowing which is which
helps when a user reports "I'm stuck on the login screen" or "it keeps
logging me out".

| Artefact | TTL | Purpose |
| --- | --- | --- |
| Access token (JWT) | 15 minutes | Authenticates every API request. |
| Refresh token | 30 days | Gets a new access token without re-login. One-time-use (rotated on each refresh). |
| Login session | 5 minutes | Holds the nonce + KDF params between the `/auth/login` challenge and `/auth/login/complete` proof steps. |
| Registration session | Per-session ExpiresAt | Carries state across email verification + password setup. |
| Password-reset session | Per-session ExpiresAt | Carries state across email verification + new-password setup. |
| WebAuthn ceremony | Per-session ExpiresAt | Short-lived challenge material for a single passkey register/assert. |
| Recovery session | See *Recovery sessions* below | Multi-hour / multi-day flow for last-device recovery. |

### Session cleanup service

A background `SessionCleanupService` runs **every hour** and prunes:

- expired `LoginSession`s, `PasswordResetSession`s, `WebAuthnCeremony`s
- pending `RecoverySession`s whose `ExpiresAt` has passed
- completed/expired sessions older than **30 days** (`CompletedRetention`)
- revoked / expired `RefreshToken`s older than 30 days
- soft-deleted vault entries older than 30 days (after they've
  replicated deletion to other devices)
- revoked `WebAuthnCredential`s older than 30 days
- revoked `VaultKeyEnvelope`s older than 30 days
- revoked `Device`s older than 30 days

Audit events are explicitly **not** cleaned up by this service — see
above.

You shouldn't normally need to touch this service. If you need to force
an early cleanup, restart the server; the interval is from startup, not
a fixed wall-clock.

### Rate limits

- **Login**: 5 failed attempts per email / 15 minutes. Exceeding returns
  HTTP 429. The next successful login resets the counter.
- **Recovery start**: 3 attempts per email / 1 hour. Designed to block
  brute-forcing recovery codes.

These are enforced by an in-memory limiter and reset on server restart.

## Recovery sessions

Recovery is the flow for "I've lost every approved device but have my
recovery codes" — distinct from password reset ("I forgot my password
but still have a signed-in device").

Lifecycle:

1. User submits a recovery code → server hashes it (Argon2id) against
   the user's stored slots. On match, a `RecoverySession` is created.
2. The session enters a **hold period** before material is released —
   24 hours by default, configurable via `Recovery:HoldPeriodHours`.
   The hold exists so that a legitimate owner who didn't initiate the
   flow has time to notice and cancel.
3. After the hold, the user can complete the flow: set a new password,
   register a fresh device, and have the server release the
   recovery-wrapped vault key. On completion a new set of recovery
   codes is issued.

Things an admin can do:

- **See active sessions**: the user detail panel lists them with
  status, release time, and expiry.
- **Cancel** (see *User management* above) — terminates the session so
  nothing is released.
- **Check the audit trail**: `recovery_code_redeemed` →
  `recovery_material_released` → `recovery_completed` is the happy path;
  `recovery_session_cancelled` and `recovery_code_failed` are the
  exceptions.

If a user reports "I started recovery but I meant to just reset my
password": cancel their session, then ask them to use the password-reset
flow from the login screen.

## Crypto parameters — don't change them

Argon2id is pinned at `m=64 MB, t=3, p=4` in server code. These values
end up baked into each user's `PasswordKdfConfig` at registration and
are used to verify every subsequent login.

**Do not try to change them.** Editing the server's pinned defaults
would not touch existing `PasswordKdfConfig` rows, and users whose
proofs were computed with the old parameters would stop being able to
log in. A real parameter-rotation story would need a migration flow
(re-wrap per user on next successful login, versioned config on each
user record) and none of that is built today.

If you ever think you need to change these, stop and file an issue —
it's a design conversation, not an operational change.

## Routine maintenance

A minimum sensible routine for a production deployment:

1. **Monitor** the server log file (`{DataDirectory}/logs/pstotp-*.log`)
   for stack traces. Serilog writes structured entries; anything at
   `ERR` or above is worth investigating.
2. **Admin-backup** before every server upgrade and on a schedule that
   matches your tolerance for data loss (weekly is reasonable for
   small instances; the file is small).
3. **DB-level backups** per your provider's story. SQLite users should
   take a copy of `{DataDirectory}/pstotp.db` during a service stop;
   Postgres / SQL Server / MySQL users should lean on `pg_dump` or the
   equivalent.
4. **Audit-log housekeeping** if the table grows uncomfortably — see
   above. Not automated.
5. **Review the admin user list in config** periodically. The `Admins`
   array is the one place privilege is decided, so it's worth
   remembering who's on it.

## When things go wrong

Short checklist before you dig in:

1. Is the service up? `systemctl status` / `docker compose ps` /
   `sc query PsTotp`.
2. What does the log say? `{DataDirectory}/logs/pstotp-*.log` is where
   Serilog writes in Production.
3. Is the user's issue account-specific or global? (Try a second
   account from a clean browser profile.)
4. Recent config change? Cookies with `__Host-` prefix, `Fido2:Origins`
   mismatch after moving hostnames, and `BasePath` mis-set after a
   proxy change are the usual suspects.

For specific symptoms and their fixes, see `docs/TROUBLESHOOTING.md`.
If you hit something that doesn't have a clear answer there, open an
issue.
