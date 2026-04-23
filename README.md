# PsTotp

**Zero-knowledge TOTP authenticator with multi-device sync.**

PsTotp is a self-hostable TOTP (time-based one-time password) authenticator
for web and Android. It encrypts every secret on the client side before
upload, so the server only ever sees ciphertext — even an administrator with
full database access can't read your codes. Multi-device sync, passkey sign-in,
recovery codes, drag-to-reorder, list and grid layouts, and drop-in imports
from Google Authenticator, Aegis, and 2FAS are all supported.

It exists because no authenticator I found gave me all of the following at
once: **total control over my OTPs**, **frictionless import/export in common
formats**, **real multi-device sync without trusting a SaaS**, and a working
**standalone mode** for people who don't want sync at all.

> **Status — roughly v0.9 / v1.0-beta.** The features most people expect of
> a TOTP app are in place and exercised daily. It has been developed and
> tested by one person; bugs you hit that the author didn't are expected.
> Ready to try, file issues. Known gaps: no iOS client, macOS builds
> available but not actively tested, SMTP-only (no OAuth2 / XOAUTH2 for
> Outlook / Gmail without app passwords). See the
> [docs backlog](docs/architecture/PLAN.md) for the full list.

## Screenshots

<!-- Replace placeholders with real screenshots under docs/images/ -->

| Vault list (web) | Vault grid (Android) |
| :--: | :--: |
| _screenshot pending — docs/images/vault-list.png_ | _screenshot pending — docs/images/vault-grid.png_ |

| First-time setup | Unlock |
| :--: | :--: |
| _screenshot pending — docs/images/setup.png_ | _screenshot pending — docs/images/unlock.png_ |

## Features

- **Zero-knowledge server.** Vault entries (issuer, account, secret, algorithm,
  digits, period) are AES-256-GCM encrypted client-side with a user-derived
  vault key. The server stores ciphertext and wrapped keys — nothing else.
- **Multi-device sync** with per-device ECDH P-256 key wrapping and explicit
  device approval from an already-approved device.
- **Unlock options.** Password (Argon2id-derived verifier, raw password never
  leaves the client), biometric (Android Keystore-bound), or WebAuthn passkey.
- **Recovery.** Recovery codes, with a configurable hold period before
  material release (defence-in-depth against stolen codes) and optional
  WebAuthn step-up.
- **Imports.** Google Authenticator transfer URIs (`otpauth-migration://`),
  Aegis plain JSON, 2FAS JSON, `otpauth://` URI lists, and PsTotp's own
  encrypted / plain JSON exports.
- **Exports.** Encrypted JSON (password-protected), plain JSON, or
  `otpauth://` URIs.
- **UI.** List and Authy-style grid layouts, drag-to-reorder, sort by
  manual / alphabetical / recently-used / most-used (with direction
  toggle), per-entry countdown rings, search, service icons.
- **Self-hosting.** Zero-config SQLite for single-user deployments, viable
  for small shared deployments too (family / small team, up to ~20 users —
  WAL mode is enabled automatically), or PostgreSQL / SQL Server / MySQL
  for larger multi-user setups. Reverse-proxy-friendly (runs at root or
  under any URL prefix).
- **Admin tooling.** User management (disable / enable / force password
  reset / delete), audit log, and a DB-independent encrypted backup /
  restore for moving between providers or snapshot-keeping.
- **Hygiene.** Clipboard auto-clear after 30 seconds on Android,
  `FLAG_SECURE` on the activity to block screenshots / screen capture,
  configurable auto-lock timeout (1 min to never).

## Who this is for

- You want total control over your OTP secrets — not stored on someone
  else's server, not tied to a vendor account.
- You want **real multi-device sync**, not a QR-scan workaround or manual
  export-import dance between phones.
- You're comfortable running a small service (Docker, systemd, or just
  double-clicking an executable on your desktop).
- You value **separation of concerns** — password manager and authenticator
  stored separately so a single compromise doesn't hand an attacker both
  factors. PsTotp explicitly does **not** try to be a password manager.

## Quick start

Two paths depending on what you want:

### Single-user, run on demand

Download a release binary (when published), double-click or launch from a
terminal, use. Nothing to configure; the server creates its own SQLite
database, generates a JWT key, and opens the browser.

```bash
# Linux / macOS
./PsTotp.Server.Api
```

```powershell
# Windows
.\PsTotp.Server.Api.exe
```

Closes cleanly via a **Shut Down** button in the UI. See
[docs/DEPLOY.md → Personal, run-on-demand](docs/DEPLOY.md#personal-run-on-demand)
for shortcuts / launchers per OS.

### Multi-user, self-hosted

Clone, configure, `docker compose up -d`:

```bash
git clone https://github.com/pstanar/pstotp.git
cd pstotp
cp docker-compose.yaml docker-compose.override.yaml  # edit secrets here
docker compose up -d
```

Front it with nginx (or your reverse proxy of choice) for TLS, point it at
Postgres, add your email to the `Admins` config to access admin tooling.
See [docs/DEPLOY.md](docs/DEPLOY.md) for the full walkthrough.

## Documentation

- **[docs/DEVELOPER.md](docs/DEVELOPER.md)** — setup, running the stack,
  adding endpoints and migrations, running tests, contributor conventions.
- **[docs/DEPLOY.md](docs/DEPLOY.md)** — deployment targets (personal,
  Docker, systemd, Windows Service, macOS), DB providers, reverse-proxy
  + HTTPS, backup strategy.
- **[docs/ADMIN.md](docs/ADMIN.md)** — daily operations: user management,
  audit review, session lifecycle, recovery-session handling.
- **[docs/CONFIG.md](docs/CONFIG.md)** — single-source reference for every
  configuration key.
- **[docs/API.md](docs/API.md)** — HTTP API narrative (auth flows,
  vault sync, optimistic concurrency, error model) with a pointer at
  the committed OpenAPI schema (`docs/openapi.json`) for field-level
  detail.
- **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** — symptom → cause
  → fix lookup.
- **[SECURITY.md](SECURITY.md)** — vulnerability disclosure policy, threat
  scope, crypto primitives, known limitations.

## Architecture in one paragraph

A .NET 10 ASP.NET Core server (minimal-API pattern, EF Core, four DB
providers via separate migration assemblies) plus a React 19 + TypeScript
web client (Vite, TanStack Router, Zustand, Web Crypto API) and a Kotlin
+ Jetpack Compose Android client. All crypto happens on the clients:
Argon2id for password-derived keys, HKDF-SHA-256 for key derivation,
AES-256-GCM for authenticated encryption, ECDH P-256 for device key
exchange, WebAuthn for passkeys. The server authenticates users via a
password-derived verifier challenge-response (so the raw password never
leaves the client) and stores only ciphertext envelopes and wrapped keys.

## Security

The one-paragraph version: the server is **not** trusted with plaintext
vault contents or raw passwords. Everything meaningful is encrypted
client-side before upload. An admin with full DB access sees only
ciphertext. Passkeys and biometric unlock are supported. Recovery has a
built-in hold period to buy time against stolen recovery codes.

For reporting vulnerabilities, threat model, crypto parameters, and known
limitations, read **[SECURITY.md](SECURITY.md)**.

## Why this is not a password manager

Authenticator and password manager are intentionally separate tools. The
second factor in "two-factor" is only valuable if it lives somewhere the
first factor doesn't. Bundling both into one app collapses that boundary
— compromise the app, compromise both factors. Use a dedicated password
manager for passwords; use PsTotp (or another dedicated authenticator)
for TOTP codes.

## Tech stack

- **Server**: .NET 10, ASP.NET Core minimal APIs, EF Core, Serilog.
  PostgreSQL / SQL Server / MySQL / SQLite via per-provider migration
  assemblies.
- **Web**: React 19 + TypeScript 5.9 (strict), Vite, TanStack Router,
  Zustand, Tailwind v4. Web Crypto API + `hash-wasm` (Argon2id),
  `@simplewebauthn/browser`.
- **Android**: Kotlin, Jetpack Compose (Material 3), Room, OkHttp,
  AndroidX Credentials (WebAuthn), Keystore-bound biometrics.
- **Crypto**: Argon2id `m=64 MB, t=3, p=4`, HKDF-SHA-256, AES-256-GCM
  with explicit AD, ECDH P-256, WebAuthn (FIDO2) with attestation `none`.

## Contributing

External contributions are welcome. See
[docs/DEVELOPER.md](docs/DEVELOPER.md) for the setup, conventions, and
how to add endpoints / migrations / tests. Non-trivial changes — and
especially anything touching crypto, sync, or the threat boundary —
should open an issue first.

## License

[Apache 2.0](LICENSE). Third-party dependency licenses are generated
into `publish/licenses/` at release time by `build.sh` / `build.ps1` and
shipped inside each release archive; PsTotp itself imposes no additional
restrictions beyond Apache 2.0's attribution clauses.
