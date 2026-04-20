# PsTotp — Configuration reference

Every configuration key the server understands, in one place. This is a
**reference** document: for how to actually wire configuration into a
specific deployment target (systemd / docker-compose / Windows Service),
see `docs/DEPLOY.md`. For routine operations, see `docs/ADMIN.md`.

## How configuration is loaded

Later wins when the same key is set in more than one place:

1. `appsettings.json` — shipped defaults (no secrets).
2. `appsettings.<Environment>.json` — shipped overlay per
   `ASPNETCORE_ENVIRONMENT` (`Development` is checked in; `Production`
   is yours to author).
3. External config file — `ConfigFile` / `PsTotpConfigFile` env var or
   `--config <path>` CLI arg. Merged on top of the built-in files.
4. Environment variables, using ASP.NET's `__` delimiter.
5. Command-line arguments (ASP.NET's standard `--Key=Value` syntax).

Zero-config startup fills in sensible defaults for everything a
single-user SQLite deployment needs — see *Zero-config behaviour* at
the bottom. Non-SQLite deployments need explicit values for the keys
marked `Required`.

All keys use PascalCase section names with `:` as the path separator
in JSON/config-file form. Environment-variable form replaces each `:`
with `__` (double underscore): `Fido2:ServerDomain` becomes
`Fido2__ServerDomain`.

Array entries use index suffixes: `Fido2:Origins:0`, `Fido2:Origins:1`,
… in config, or `Fido2__Origins__0=...` as an env var.

## Database

### `DatabaseProvider`

- Type: `string` (one of `PostgreSQL`, `SqlServer`, `MySql`, `SQLite`)
- Default: unset → zero-config SQLite fallback
- Env var: `DatabaseProvider`
- Purpose: Selects which EF Core provider and migrations assembly to
  use. If unset and `ConnectionStrings:PsTotpDb` is also empty, the
  server creates a SQLite database under the data directory.

### `ConnectionStrings:PsTotpDb`

- Type: `string`
- Default: unset → zero-config SQLite; for the shipped Development
  overlay, `Host=localhost;Port=5432;Database=pstotp;Username=pstotp;Password=pstotp`
- Env var: `ConnectionStrings__PsTotpDb`
- Purpose: Database connection string for the selected provider.
- Notes: Credentials are stripped from startup logs. For docker-compose
  the host is usually the service name (`Host=db;...`).

### `Database:ApplyMigrationsOnStartup`

- Type: `bool`
- Default: `false` for non-SQLite providers (SQLite always auto-migrates).
- Env var: `Database__ApplyMigrationsOnStartup`
- Purpose: When `true`, the server applies pending EF Core migrations
  at startup, the same way the zero-config SQLite fallback already does.
- Notes: Convenience for single-instance hobbyist deployments. For
  production / multi-instance / strict-uptime deployments, prefer the
  out-of-band `PsTotp.Server.Api --migrate` step (see `docs/DEPLOY.md`
  → *Upgrade / migration workflow*) so migration failures don't become
  startup restart loops.

## Data directory and files

### `DataDirectory`

- Type: `string` (absolute path)
- Default: `%APPDATA%\pstotp` on Windows, `~/.pstotp` on Linux/macOS
- Env var: `DataDirectory`
- Purpose: Root directory for SQLite DB, rolling log files, and the
  auto-generated JWT secret (zero-config only).
- Notes: The `PSTOTP_DATA` environment variable takes priority over
  this key. Resolution order: `PSTOTP_DATA` → `DataDirectory` →
  platform default.

### `PSTOTP_DATA`

- **Environment variable only** (has no config-file equivalent).
- Type: `string` (absolute path)
- Purpose: Override for `DataDirectory`. Useful in systemd /
  docker-compose where the data path is part of the infrastructure,
  not the app.

### `ConfigFile` / `PsTotpConfigFile`

- **Environment variable** (either name works); or `--config <path>`
  CLI arg; or config-file key.
- Type: `string` (absolute path)
- Purpose: Path to an external JSON config file merged on top of
  `appsettings.json` and `appsettings.<Env>.json`.
- Notes: Handy for keeping production secrets out of the deployed
  directory: put the main binary in `/opt/pstotp/` and point to
  `/etc/pstotp/appsettings.Production.json` via this variable.

## JWT

### `Jwt:Secret`

- Type: `string` (base64-encoded 256-bit key)
- Default: auto-generated and persisted to
  `{DataDirectory}/jwt-secret.key` in zero-config SQLite mode only.
- Env var: `Jwt__Secret`
- Purpose: Symmetric signing key for access and refresh JWTs.
- Notes: **Required** in non-zero-config deployments. Generate with
  `openssl rand -base64 32`. Rotating it invalidates every outstanding
  access and refresh token — users will be forced to sign in again.

### `Jwt:Issuer`

- Type: `string`
- Default: `pstotp`
- Env var: `Jwt__Issuer`
- Purpose: The `iss` claim stamped into issued tokens and validated
  on incoming ones.
- Notes: You almost never need to change this. If you do, change it
  atomically — tokens issued under the old issuer stop validating.

### `Jwt:Audience`

- Type: `string`
- Default: `pstotp`
- Env var: `Jwt__Audience`
- Purpose: The `aud` claim stamped into issued tokens and validated
  on incoming ones.
- Notes: Same caveat as `Jwt:Issuer`.

## WebAuthn / FIDO2

### `Fido2:ServerDomain`

- Type: `string` (bare hostname, no scheme, no port)
- Default: `localhost`
- Env var: `Fido2__ServerDomain`
- Purpose: The RP ID presented to the browser/Credential Manager
  during every WebAuthn ceremony.
- Notes: **Changing this invalidates every registered passkey.**
  Users will need to register new ones. Must be the apex of the origin
  serving the web client (or a registrable ancestor).

### `Fido2:ServerName`

- Type: `string`
- Default: `PsTotp`
- Env var: `Fido2__ServerName`
- Purpose: Human-readable RP name shown in the browser's passkey
  prompt. Cosmetic.

### `Fido2:Origins`

- Type: `string[]`
- Default: built from `AllowedOrigins` in zero-config, else required.
- Env var: `Fido2__Origins__0=https://example.com`, `Fido2__Origins__1=...`
- Purpose: Exact list of origins (scheme + host [+ port]) that may
  initiate WebAuthn ceremonies. Mismatch causes the browser/Credential
  Manager to reject the ceremony.
- Notes: Use the full origin: `https://totp.example.com`, not
  `totp.example.com` or `https://totp.example.com/`.

### `Android:PackageName`

- Type: `string`
- Default: unset — no Android origin registered.
- Env var: `Android__PackageName`
- Purpose: Android app package name (e.g. `net.stanar.pstotp`) used
  when the server auto-generates the `android:apk-key-hash:...`
  WebAuthn origin for Credential Manager.

### `Android:CertFingerprints`

- Type: `string[]` (SHA-256 fingerprints, uppercase colon-separated hex)
- Default: unset — no Android origin registered.
- Env var: `Android__CertFingerprints__0=AA:BB:CC:...`
- Purpose: Signing certificate fingerprints for the Android app. The
  server auto-generates one `android:apk-key-hash:...` origin per
  fingerprint and adds it to the allowed WebAuthn origins list.
- Notes: You need the debug-keystore fingerprint for development and
  the release-keystore fingerprint for production. `gradlew signingReport`
  or `keytool -printcert -jarfile <apk>`.

## CORS and hosting

### `AllowedOrigins`

- Type: `string` (semicolon-separated list of origins)
- Default: unset; shipped Development overlay has `http://localhost:5173`.
- Env var: `AllowedOrigins`
- Purpose: CORS allow-list for browsers calling the API from another
  origin (typical: Vite dev server, or a split deployment where the
  SPA is hosted separately).
- Notes: Use full origins with scheme. For the typical deployment
  (SPA served by the same API host) you don't need this set, because
  the SPA and API share an origin.

### `BasePath`

- Type: `string`
- Default: `""` (served at root)
- Env var: `BasePath`
- Purpose: URL path prefix when the server runs behind a reverse
  proxy that forwards `/prefix/...` to the server unchanged.
  Sets `UsePathBase` and threads the value into the SPA via
  runtime substitution of `__BASE_PATH__` in `index.html`.
- Notes: Match the proxy's `location` — `/totp`, not `/totp/`. See
  `docs/DEPLOY.md` → *Reverse proxy and HTTPS* for the full story.

### `ReverseProxy:KnownProxies`

- Type: `string[]` (IP addresses)
- Default: loopback (`127.0.0.1`, `::1`) trusted; nothing else.
- Env var: `ReverseProxy__KnownProxies__0=10.0.0.1`
- Purpose: IPs whose `X-Forwarded-*` headers the server will trust.
  Without this set for a non-loopback proxy, the server will not
  honour the forwarded scheme/IP and HTTPS-aware logic (cookie
  Secure flag, redirects) breaks.

### `ASPNETCORE_URLS`

- **Environment variable only** (standard ASP.NET key).
- Type: `string` (semicolon-separated URL bindings)
- Default: `http://0.0.0.0:5000` in zero-config; `http://localhost:5245`
  in the shipped Development launch profile.
- Purpose: Which addresses/ports the Kestrel server binds.
- Notes: Use `http://127.0.0.1:5000` to keep the service bound to
  loopback only; useful for "run behind a reverse proxy" setups where
  you don't want anyone reaching Kestrel directly.

## Self-hosting UX toggles

### `EnableHttps`

- Type: `bool`
- Default: `false`
- Env var: `EnableHttps`
- Purpose: When `true`, Kestrel binds port 5001 with a self-signed
  certificate in addition to the HTTP port.
- Notes: **Dev / LAN only.** Do not enable this for internet-facing
  deployments — passkey RP validation is finicky with self-signed
  certs and browsers will warn your users. Production deployments
  terminate TLS at a reverse proxy with a real certificate.

### `EnableShutdown`

- Type: `bool`
- Default: `true` when the server is running zero-config SQLite
  standalone (single-user), `false` otherwise.
- Env var: `EnableShutdown`
- Purpose: When `true`, exposes a **Shut Down** action in the web UI
  that an authenticated user can trigger to stop the service cleanly.
- Notes: Intended for the desktop / double-click-the-EXE use case.
  **Do not enable in multi-user or server deployments** — it would
  let any authenticated user shut the service down.

### `OpenBrowser`

- Type: `bool`
- Default: `true` when the server is running zero-config SQLite
  standalone; `false` otherwise.
- Env var: `OpenBrowser`
- Purpose: When `true`, the server opens the system default browser
  to the server's URL at startup. Handy for double-click use.
- Notes: Set to `false` for headless / systemd / Docker deployments.

## Admin

### `Admins`

- Type: `string[]` (email addresses)
- Default: `[]`
- Env var: `Admins__0=you@example.com`
- Purpose: Emails whose accounts are granted the `Admin` role on
  login. The role is stamped into the JWT at login time.
- Notes: Role is applied per-login. Adding someone to this list
  doesn't affect an already-signed-in session — they have to sign
  out and back in. Removing someone means their next-issued token
  won't carry admin. See `docs/ADMIN.md` for the authorisation
  semantics.

## Email

Leaving `Email:SmtpHost` empty selects the `NullEmailService` fallback,
which returns verification codes inline in the API response so the
flow works without a real mail server. Useful for dev / single-user.

### `Email:SmtpHost`

- Type: `string`
- Default: unset → `NullEmailService`
- Env var: `Email__SmtpHost`
- Purpose: SMTP server host. Presence of this key toggles the real
  `SmtpEmailService` on.

### `Email:SmtpPort`

- Type: `int`
- Default: `587`
- Env var: `Email__SmtpPort`
- Purpose: SMTP port. `465` triggers implicit TLS (`SslOnConnect`);
  anything else uses STARTTLS.

### `Email:Username`, `Email:Password`

- Type: `string`
- Default: unset (required when `Email:SmtpHost` is set)
- Env var: `Email__Username`, `Email__Password`
- Purpose: SMTP auth credentials.
- Notes: Basic SMTP auth only — XOAUTH2 (Outlook.com, Google without
  app passwords) is tracked in `memory/future_work.md`.

### `Email:FromAddress`

- Type: `string`
- Default: falls back to `Email:Username`
- Env var: `Email__FromAddress`
- Purpose: `From:` header of outgoing mail.

### `Email:FromName`

- Type: `string`
- Default: `PsTotp`
- Env var: `Email__FromName`
- Purpose: Display-name part of the `From:` header.

## Registration

### `Registration:RequireEmailVerification`

- Type: `bool`
- Default: `false`
- Env var: `Registration__RequireEmailVerification`
- Purpose: When `true`, registration sends a verification code to the
  supplied email address and refuses to finalise the account without
  it. When `false`, the verification step is skipped.
- Notes: Enabling this with no SMTP configured leaves users unable
  to register — the `NullEmailService` returns the code inline but
  most clients don't surface that. Pair it with a working
  `Email:SmtpHost`.

## Recovery

### `Recovery:HoldPeriodHours`

- Type: `int`
- Default: `24`
- Env var: `Recovery__HoldPeriodHours`
- Purpose: Number of hours between a successful recovery-code
  redemption and the point at which vault-key material can be
  released. Exists so a legitimate owner has time to notice a
  hostile attempt and cancel the session.
- Notes: Lower values reduce defence-in-depth. Don't set this to
  zero in any production-like deployment.

## Logging

`Serilog:*` — standard Serilog configuration section. PsTotp ships
sensible defaults (console in Development, rolling daily file in
Production under `{DataDirectory}/logs/pstotp-*.log` with 30-day
retention). Refer to the
[Serilog configuration docs](https://github.com/serilog/serilog-settings-configuration)
for the full schema if you need to customise further — we don't try
to re-document Serilog here.

If you set *any* `Serilog:WriteTo` sink in config, the auto-configured
defaults are skipped and you're responsible for the full configuration.

## ASP.NET framework keys

The framework keys you're most likely to touch:

### `ASPNETCORE_ENVIRONMENT`

- Env var only. Values: `Development`, `Production`, `Testing`, or any
  custom string that maps to an `appsettings.<name>.json` overlay.
- Drives which overlay loads and enables dev-time behaviours (auto-
  migrate for non-SQLite, console logging, Vite CORS, Scalar API
  docs).

### `DOTNET_ENVIRONMENT`

- Env var only. Same semantics as `ASPNETCORE_ENVIRONMENT` but
  lower-priority when both are set.

### `Kestrel:Endpoints`

- Section. Use for custom binding configuration (explicit HTTPS
  certs, HTTP/3, unix sockets).
- If this is set, the server assumes you know what you're doing and
  disables its own endpoint auto-configuration.

## Zero-config behaviour

If `DatabaseProvider` is unset and `ConnectionStrings:PsTotpDb` is
empty, the server classifies itself as "zero-config SQLite standalone"
and fills in:

- `DatabaseProvider = SQLite`
- `ConnectionStrings:PsTotpDb = Data Source={DataDirectory}/pstotp.db`
- `Jwt:Secret` — auto-generated 256-bit key, persisted to
  `{DataDirectory}/jwt-secret.key`.
- `Fido2:ServerDomain = localhost`; `Fido2:Origins` built from the
  current Kestrel URLs.
- `AllowedOrigins` built from the same URLs.
- `EnableShutdown = true` and `OpenBrowser = true` (defaults flip to
  `false` the moment the server is running anything else).

This is the mode the desktop "run-on-demand" scenario relies on. See
`docs/DEPLOY.md` → *Personal, run-on-demand* for context.

## Example configurations

### Single-user, zero-config

Nothing to set. Launch the binary, it creates the data directory,
generates a JWT secret, binds `http://0.0.0.0:5000`, opens a browser.

### Postgres behind nginx at root

```json
{
  "DatabaseProvider": "PostgreSQL",
  "ConnectionStrings": {
    "PsTotpDb": "Host=localhost;Port=5432;Database=pstotp;Username=pstotp;Password=<redacted>"
  },
  "Jwt": { "Secret": "<base64-256-bit>" },
  "AllowedOrigins": "https://totp.example.com",
  "Fido2": {
    "ServerDomain": "totp.example.com",
    "Origins": [ "https://totp.example.com" ]
  },
  "ReverseProxy": { "KnownProxies": [ "127.0.0.1" ] },
  "Admins": [ "you@example.com" ],
  "EnableShutdown": false,
  "OpenBrowser": false
}
```

### Postgres behind nginx under /totp prefix

Same as above, with one extra key and an adjusted `Fido2:ServerDomain`
pointing at the apex (so Android `assetlinks.json` works):

```json
{
  "BasePath": "/totp",
  "AllowedOrigins": "https://example.com",
  "Fido2": {
    "ServerDomain": "example.com",
    "Origins": [ "https://example.com" ]
  }
}
```

### SMTP-enabled deployment

Add to any of the above:

```json
{
  "Email": {
    "SmtpHost": "smtp.example.com",
    "SmtpPort": 587,
    "Username": "pstotp@example.com",
    "Password": "<redacted>",
    "FromAddress": "pstotp@example.com",
    "FromName": "PsTotp"
  },
  "Registration": { "RequireEmailVerification": true }
}
```
