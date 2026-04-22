# PsTotp — Deployment Guide

This document covers running PsTotp in production: building a release,
choosing a deployment target, fronting it with a reverse proxy and HTTPS,
handling secrets, and backup.

For development setup and coding workflow, see `docs/DEVELOPER.md`.
For design and architecture context, see `docs/architecture/PLAN.md`.

## Release artifacts

The project is at the "clone and build locally" stage today. Pre-built
binaries attached to GitHub releases are planned; a public Docker image
may or may not follow — see `memory/future_work.md`.

Building a release from source:

```bash
# Linux / macOS
./build.sh

# Windows
.\build.ps1
```

The script derives the version from the nearest `git` tag (falling back to
`0.0.0`), adds the number of commits since that tag as the build number,
and a short SHA as metadata. Running either script requires the .NET SDK,
Node.js, and — if you want the Android APK — a JDK 17+ plus the Android
SDK. Output lands in `publish/`:

- `pstotp-<version>-win-x64-{self-contained,framework-dependent}.zip`
- `pstotp-<version>-linux-x64-{self-contained,framework-dependent}.tar.gz`
- `pstotp-<version>-osx-arm64-{self-contained,framework-dependent}.tar.gz`
- `pstotp-<version>-android-debug.apk` — Android debug APK (only produced
  when `ANDROID_HOME` / `ANDROID_SDK_ROOT` is set; release-signed APK is
  not wired up yet)
- `licenses/` — NuGet + npm attribution manifests (also copied inside
  every archive)
- `SHA256SUMS` — checksums for every `pstotp-*` artifact

Each self-contained build includes the .NET runtime and the embedded
web SPA, so the deployed artifact has no framework dependency and no
separate `wwwroot`. The script also tags a `pstotp:latest` / `pstotp:<version>`
Docker image of the server when it finishes; set `SKIP_DOCKER_IMAGE=1`
to turn that off.

### Building without a local toolchain

If you have Docker but no .NET SDK / Node / JDK / Android SDK, run the
whole pipeline in a container:

```bash
docker build -f Dockerfile.build -o publish .
```

That builds a throwaway image carrying every toolchain, runs `build.sh`
inside it (with `SKIP_DOCKER_IMAGE=1`), and exports `publish/` to the
host — producing byte-identical artifacts to a native build. The server
runtime image itself is still built by the main `Dockerfile` on the host
(`docker build -t pstotp .`); building an image from inside a container
would need Docker-in-Docker and isn't worth it when you already have
Docker on the host.

## Picking a deployment target

PsTotp ships as a plain process with no external runtime dependencies
(the self-contained builds include the .NET runtime and the embedded
SPA). You can host it through any mechanism that can launch a process
and keep it running:

- **Docker / docker-compose** — the path with the shortest "copy this
  `docker-compose.yaml` and go" story. Recommended when you already run
  containers and want Postgres alongside.
- **A native service / daemon** — `systemd` on Linux, a Windows Service
  on Windows, `launchd` on macOS. Recommended when you prefer not to
  add Docker to your stack, or are fronting an existing host that
  already runs other services natively.
- **A scheduled / user-session launcher** — Windows Task Scheduler
  ("At startup" or "At logon"), a Start-up folder shortcut, an
  `xdg-autostart` `.desktop` file on a desktop Linux, or a macOS
  Launch Agent. Lightweight, single-user-centric. Suits the
  home-desktop-always-on case without a dedicated service account.
- **The binary directly** — just launch it when you need it and shut
  down when done. Suits the desktop-tool pattern.

None of these is more "supported" than the others; pick the one that
matches the rest of your infrastructure. The table below matches the
common scenarios to a suggested path; all options are covered in more
detail in the sections that follow.

| Scenario | Recommended path |
| --- | --- |
| Personal single-user, run-on-demand | Run the self-contained binary directly — no service / daemon / container |
| Personal / LAN / always-on (desktop) | Task Scheduler / startup entry / autostart — service-free |
| Personal / LAN / always-on (server box) | systemd unit, Windows Service, or Docker — whichever fits the host |
| Small shared (≤ ~20 users, family/small team) | Any of the above with SQLite — see *SQLite (small hosted)* below |
| Small-to-medium self-host | Postgres backend (native or Docker), behind nginx |
| Existing Windows Server with SQL Server | Windows Service, SQL Server provider |
| Server administrators comfortable with Postgres | Linux systemd + Postgres + nginx |
| macOS | Best-effort — see note below |

## Personal, run-on-demand

Simplest path: a single self-contained binary you launch when you need
the app and shut down when you're done. No service registration, no
container, no reverse proxy. It suits the single-user case where you
don't need background sync to multiple devices — you open the app,
check or add codes, close it.

With the zero-config SQLite fallback the binary does everything on its
own:

- Creates the data directory on first run (`%APPDATA%\pstotp` on Windows,
  `~/.pstotp` on Linux/macOS).
- Auto-generates a JWT signing key and the SQLite database.
- Binds `http://0.0.0.0:5000`, opens your default browser at that
  address, and enables the in-app **Shut Down** button so you can exit
  cleanly without a terminal.

Launch:

```bash
# Linux / macOS — self-contained binary, no runtime needed
./publish/linux-x64/PsTotp.Server.Api
# or, from a source checkout:
dotnet run --project src/Server.Api/PsTotp.Server.Api.csproj
```

```powershell
# Windows — double-click or run
.\publish\win-x64\PsTotp.Server.Api.exe
```

To quit: click the **Shut Down** button in the top bar of the web UI, or
`Ctrl+C` in the terminal if you launched from one.

### Desktop shortcut

Double-clicking the EXE / launching from Finder / a desktop launcher
makes this feel like a regular desktop app.

**Windows**: right-click the desktop → **New → Shortcut** → browse to
`PsTotp.Server.Api.exe`. Right-click the shortcut → **Properties** →
**Run:** `Minimized` if you don't want the console window on top. Pin
to Start or Taskbar as usual. You can also put the EXE under a
`%LOCALAPPDATA%\Programs\PsTotp\` directory and add it to Start via a
shortcut there.

**Linux**: drop a `.desktop` file into `~/.local/share/applications/`:

```ini
# ~/.local/share/applications/pstotp.desktop
[Desktop Entry]
Type=Application
Name=PsTotp
Comment=TOTP authenticator
Exec=/opt/pstotp/PsTotp.Server.Api
Icon=/opt/pstotp/icon.png
Terminal=false
Categories=Utility;Security;
```

`chmod +x` the desktop file if your DE requires it. It'll show up in
the application menu and can be pinned to dock/panel.

**macOS**: place the binary under `/Applications/PsTotp/` (or wherever
you prefer) and either drag it to the Dock, or wrap it in a small
AppleScript applet via Script Editor → **File → Export → Application**
running `do shell script "/path/to/PsTotp.Server.Api &"`.

### Behavioural notes

- `EnableShutdown` is auto-on for the zero-config SQLite case. If you
  move to Postgres or put the binary behind any kind of reverse proxy,
  set `EnableShutdown=false` explicitly — you don't want a random
  authenticated client putting your server to sleep.
- `OpenBrowser` is also auto-on for zero-config SQLite. Set
  `OpenBrowser=false` if you're launching it headlessly (e.g. from a
  startup script and connecting from another device on the LAN).
- The data directory and log files stick around between runs — closing
  the window doesn't wipe anything. Your vault persists across launches.
- Because it listens on `0.0.0.0` by default, other devices on your LAN
  can reach it at `http://<your-hostname>:5000`. If you only want it
  accessible from the same machine, bind to loopback by setting
  `ASPNETCORE_URLS=http://127.0.0.1:5000`.

## Lightweight always-on launchers (no service registration)

When the host is a regular desktop or laptop that's always on, you
often don't want the ceremony of installing a system service. The
OS-native user-session launchers handle this well and avoid needing
root / admin rights.

Use these when:
- You're the only user of the box.
- The service only needs to run while you're logged in (or while the
  machine is on if you configure "at startup" rather than "at logon").
- You don't want a dedicated service account / permission story.

### Windows — Task Scheduler

Launch PsTotp at startup or logon, no service needed:

```powershell
$exe = "C:\Program Files\PsTotp\PsTotp.Server.Api.exe"
$action = New-ScheduledTaskAction -Execute $exe
$trigger = New-ScheduledTaskTrigger -AtStartup
# Or: -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "PsTotp" `
    -Action $action -Trigger $trigger -Settings $settings `
    -RunLevel Highest -Description "PsTotp authenticator"
```

Because Task Scheduler launches the process outside any interactive
session, set `OpenBrowser=false` so it doesn't try to open a browser
that nobody's there to see. `EnableShutdown` can stay on if this is
your single-user box — you still want the in-app **Shut Down** button.

### Windows — Startup folder shortcut

Even lighter: drop a shortcut to the `.exe` into
`shell:startup` (user-scoped) or `shell:common startup` (all users).
Launches after logon, no scheduler involved. Good for the
"it's literally my own machine" case.

### Linux desktop — XDG autostart

Create `~/.config/autostart/pstotp.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=PsTotp
Exec=/opt/pstotp/PsTotp.Server.Api
Terminal=false
X-GNOME-Autostart-enabled=true
```

Runs when you log into the desktop session. For a headless server
that just happens to live on Linux, use the `systemd` unit below
instead.

### macOS — user-scoped Launch Agent

Same plist format as the LaunchDaemon in the macOS section below, but
dropped into `~/Library/LaunchAgents/` instead of
`/Library/LaunchDaemons/` and loaded without `sudo`. Agent runs only
for the current user's session; Daemon runs system-wide.

## Docker / docker-compose

The `docker-compose.yaml` in the repo root ships a working example:
Postgres 18 + the server, with a named volume for app data (`%APPDATA%\pstotp`
equivalent) and another for Postgres data. **The credentials and secrets in
it are stand-in placeholders you should override before exposing the
service anywhere.**

```bash
# Build the image and bring both services up.
docker compose up -d --build

# Tail logs.
docker compose logs -f app

# Stop.
docker compose down
```

### Configuration in production

The shipped compose file sets these environment variables on `app`:

```yaml
environment:
  - DatabaseProvider=PostgreSQL
  - ConnectionStrings__PsTotpDb=Host=db;Database=pstotp;Username=pstotp;Password=pstotp
```

For a real deployment, replace the inline values with one of:

- **A `.env` file next to `docker-compose.yaml`** with real secrets, plus
  `env_file: .env` on the `app` service. Add `.env` to your operational
  gitignore.

  ```
  # .env
  DB_PASSWORD=<real password>
  JWT_SECRET=<base64 256-bit>
  ```

  ```yaml
  # docker-compose.override.yaml
  services:
    app:
      env_file: .env
      environment:
        - ConnectionStrings__PsTotpDb=Host=db;Database=pstotp;Username=pstotp;Password=${DB_PASSWORD}
        - Jwt__Secret=${JWT_SECRET}
    db:
      environment:
        - POSTGRES_PASSWORD=${DB_PASSWORD}
  ```

- **Docker secrets** (Swarm / Kubernetes): mount the values as files under
  `/run/secrets/` and point `ConnectionStrings__PsTotpDb`/`Jwt__Secret` at
  them via a small entrypoint script, or use configuration providers that
  read from secret stores.

- **An external config file** mounted into the container at a known path.
  The app accepts a config file via `ConfigFile` or `PsTotpConfigFile`
  environment variables or the `--config <path>` CLI arg. This file is
  layered on top of the built-in `appsettings.json`.

Required config keys in production (beyond what zero-config handles):

| Key | Purpose |
| --- | --- |
| `DatabaseProvider` | `PostgreSQL`, `SqlServer`, `MySql`, or `SQLite`. |
| `ConnectionStrings:PsTotpDb` | Connection string for the chosen provider. |
| `Jwt:Secret` | Base64-encoded 256-bit symmetric key. Auto-generated only for zero-config SQLite; supply your own otherwise. |
| `Fido2:ServerDomain` | The RP ID for WebAuthn — must match the external hostname users see. |
| `Fido2:Origins` | Array of allowed WebAuthn origins (https URLs, including scheme). |
| `AllowedOrigins` | CORS origins (semicolon-separated) — normally the same external origin. |
| `BasePath` | Path prefix when serving under a reverse proxy (e.g. `/totp`), empty to serve at root. |
| `ReverseProxy:KnownProxies` | Array of trusted proxy IPs for `X-Forwarded-*` headers. Defaults to loopback. |

`appsettings.json` (shipped) has safe defaults for the non-sensitive
settings; only the items above need to be overridden.

### Data volume

The `app-data` volume holds the SQLite DB (unused here since we're on
Postgres), the JWT secret key file (if auto-generated), and rolling daily
log files. Keep it persisted across upgrades.

## Linux systemd

On a host with the .NET 10 runtime or a self-contained Linux build placed
at `/opt/pstotp/`:

```ini
# /etc/systemd/system/pstotp.service
[Unit]
Description=PsTotp TOTP sync service
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
User=pstotp
Group=pstotp
WorkingDirectory=/opt/pstotp
ExecStart=/opt/pstotp/PsTotp.Server.Api
Restart=on-failure
RestartSec=5
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=PSTOTP_DATA=/var/lib/pstotp
Environment=ConfigFile=/etc/pstotp/appsettings.Production.json
# EnableShutdown is auto-off when DatabaseProvider isn't SQLite, but set
# it explicitly in case you're running SQLite on a headless server.
Environment=EnableShutdown=false

[Install]
WantedBy=multi-user.target
```

```bash
# Create a service user with no shell and a data directory owned by it.
sudo useradd --system --home-dir /var/lib/pstotp --shell /usr/sbin/nologin pstotp
sudo install -d -o pstotp -g pstotp /var/lib/pstotp /etc/pstotp

# Drop your appsettings.Production.json (with DatabaseProvider, connection
# string, Jwt:Secret, Fido2 settings, BasePath, etc.) into /etc/pstotp/.

sudo systemctl daemon-reload
sudo systemctl enable --now pstotp
sudo journalctl -u pstotp -f     # live logs (also written to $PSTOTP_DATA/logs/)
```

`PSTOTP_DATA=/var/lib/pstotp` overrides the default data directory so
logs, generated keys, and (for SQLite) the database end up under a
conventional Linux FHS path instead of `~pstotp/.pstotp`. Rolling daily
log files are retained for 30 days.

## Windows Service

After running `build.ps1`, register the Windows service with `sc.exe`:

```powershell
# Drop the published binary + wwwroot + appsettings.json under a stable path.
$target = "C:\Program Files\PsTotp"
New-Item -ItemType Directory -Force $target | Out-Null
Copy-Item .\publish\win-x64\* $target -Recurse

# Create the data directory, writable by the service account.
$data = "C:\ProgramData\PsTotp"
New-Item -ItemType Directory -Force $data | Out-Null

# Install + start the service.
sc.exe create PsTotp binPath= "`"$target\PsTotp.Server.Api.exe`"" start= auto
sc.exe description PsTotp "PsTotp TOTP sync service"
sc.exe start PsTotp
```

Environment variables for the service:

```powershell
# Set machine-scope env vars so the service picks them up on next restart.
[Environment]::SetEnvironmentVariable("ASPNETCORE_ENVIRONMENT", "Production", "Machine")
[Environment]::SetEnvironmentVariable("PSTOTP_DATA", "C:\ProgramData\PsTotp", "Machine")
[Environment]::SetEnvironmentVariable("ConfigFile", "C:\ProgramData\PsTotp\appsettings.Production.json", "Machine")
[Environment]::SetEnvironmentVariable("EnableShutdown", "false", "Machine")
```

Place `appsettings.Production.json` with real config in
`C:\ProgramData\PsTotp\`. Logs land under `C:\ProgramData\PsTotp\logs\` as
daily rolling files.

Turning `EnableShutdown` off is especially important on Windows Server:
with it on, anyone authenticated can shut the service down from the UI,
and Windows will not automatically restart it.

## macOS

macOS is a best-effort target. The author does not own Apple hardware and
does not regularly run the stack there. The self-contained `osx-arm64`
build in `publish/` should launch, but issues are resolved on a
best-effort basis only.

A minimal `launchd` plist for running as a LaunchDaemon:

```xml
<!-- /Library/LaunchDaemons/info.stanar.pstotp.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>              <string>info.stanar.pstotp</string>
  <key>ProgramArguments</key>   <array>
    <string>/opt/pstotp/PsTotp.Server.Api</string>
  </array>
  <key>RunAtLoad</key>          <true/>
  <key>KeepAlive</key>          <true/>
  <key>WorkingDirectory</key>   <string>/opt/pstotp</string>
  <key>StandardOutPath</key>    <string>/var/log/pstotp.log</string>
  <key>StandardErrorPath</key>  <string>/var/log/pstotp.err</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>ASPNETCORE_ENVIRONMENT</key> <string>Production</string>
    <key>PSTOTP_DATA</key>            <string>/Library/Application Support/PsTotp</string>
    <key>ConfigFile</key>             <string>/Library/Application Support/PsTotp/appsettings.Production.json</string>
  </dict>
</dict>
</plist>
```

```bash
sudo launchctl load /Library/LaunchDaemons/info.stanar.pstotp.plist
```

This has not been verified against a production macOS host. Report bugs
as you find them.

## Database in production

### SQLite (zero-config single-user)

Auto-selected when `DatabaseProvider` is unset and `ConnectionStrings:PsTotpDb`
is empty. Appropriate for single-user / LAN / hobbyist deployments. The
database file lives at `{DataDirectory}/pstotp.db`. Migrations apply
automatically on startup in every environment, and the server enables
WAL journaling on first boot so concurrent reads don't block in-flight
writes.

### SQLite (small hosted — up to ~20 users)

SQLite is also viable for small shared deployments (family / small team).
PsTotp enables WAL journal mode on SQLite at startup, so a handful of
users logging in, syncing vaults, and writing audit events concurrently
doesn't serialise on a single writer lock.

The hosted-SQLite recipe differs from the run-on-demand desktop one in
two config settings:

```json
{
  "DatabaseProvider": "SQLite",
  "ConnectionStrings": { "PsTotpDb": "Data Source=/var/lib/pstotp/pstotp.db" },
  "EnableShutdown": false,
  "OpenBrowser": false,
  "Jwt": { "Secret": "<base64-256-bit>" },
  "AllowedOrigins": "https://totp.example.com",
  "Fido2": {
    "ServerDomain": "totp.example.com",
    "Origins": [ "https://totp.example.com" ]
  },
  "Admins": [ "you@example.com" ]
}
```

`EnableShutdown=false` is **critical**: otherwise any authenticated user
can hit `POST /api/system/shutdown` and stop the service. It auto-enables
for the zero-config SQLite case (which assumes desktop run-on-demand).

**Backup discipline.** Don't `cp pstotp.db` while the service is running
— WAL mode means the database state is spread across `pstotp.db`,
`pstotp.db-wal`, and `pstotp.db-shm`, and a raw copy during a write can
produce a corrupt backup. Either:

- **Stop the service**, copy all three files (or just the whole data
  directory), restart. Simplest and always safe.
- **Online backup** via `sqlite3 /var/lib/pstotp/pstotp.db ".backup /var/backups/pstotp-$(date +%F).db"`.
  Atomic, concurrent-writer-safe, produces a single self-contained file.
- The admin DB backup endpoint works the same way as for any other
  provider — see *Backup and restore* above. DB-independent,
  admin-password-encrypted, ideal for moving to Postgres later.

**When to graduate to Postgres.** Rough rule of thumb: up to ~20 users is
comfortable SQLite territory. Past that, concurrent writes start
queuing, and proper online backup / replication / horizontal scaling
become reasons to run a real DB server. The admin backup gives you a
clean migration path whenever you decide to switch.

### PostgreSQL / SQL Server / MySQL

For larger-scale deployments, pick one of these. You are expected to
manage the database lifecycle: creation, user/permission setup, backups,
monitoring. PsTotp expects a pre-existing, empty database on first start
and will run migrations against it in **Development only**.

**In Production**, migrations do NOT apply automatically for non-SQLite
providers. You must apply them deliberately on every upgrade — see the
next section.

### Upgrade / migration workflow

Non-SQLite deployments don't auto-apply migrations on startup, by
design — a server that fails to start because of a half-applied schema
is a bad failure mode. The server binary itself carries the
migrations; there are two supported ways to apply them.

**Option A — explicit migrate step (recommended for production).**
The server binary accepts a `--migrate` flag that applies pending
migrations and exits. Intended as a dedicated step in your deployment
pipeline, separate from serving traffic.

```bash
# Stop the running service.
# Deploy the new binary to its install location.
# Run migrate against the same config the service uses:
PsTotp.Server.Api --migrate
# Exit code 0 on success (or no pending migrations), 1 on failure.
# Start the service.
```

The migrate step reads the same configuration as the normal server
(connection string, `DatabaseProvider`, env vars), so no extra plumbing
is needed. It logs the pending migration list before applying, and
exits non-zero on failure so pipelines can gate the service restart on
a successful migration.

**Option B — apply on startup (convenience for hobbyist deployments).**
Set `Database:ApplyMigrationsOnStartup=true` in config and the server
will apply pending migrations at boot, the same way SQLite already
does. Simple, but:

- Failed migrations become startup failures, which in a supervised
  setup (systemd / docker) means restart loops.
- If you run more than one instance, they'll race on the migration on
  startup; pick one.

For a single-instance self-host where uptime forgiveness is cheap,
this is fine. For anything with multiple instances or strict uptime
requirements, stick with Option A.

**SQLite deployments** don't need either — migrations always auto-apply
at startup. Upgrade is "replace the binary and restart".

## Reverse proxy and HTTPS

PsTotp can bind HTTPS directly with a self-signed cert (`EnableHttps=true`
on port 5001), but that path is intended for dev / LAN testing only.
Production deployments terminate TLS at a reverse proxy with a real
certificate (Let's Encrypt or your CA of choice). The server then listens
plain HTTP on loopback or a private network.

Pipeline expectations when running behind a proxy:

- `UseForwardedHeaders` runs early, so the server sees the client's
  original scheme and address via `X-Forwarded-Proto` / `X-Forwarded-For`.
- `ReverseProxy:KnownProxies` must include the proxy's IP (or IP range)
  for those headers to be trusted. Loopback is allowed by default.
- `BasePath` lets the server serve under a path prefix. Leave it empty
  when proxying to the site root; set it to e.g. `/totp` when the site
  is served under a sub-path. The server calls `UsePathBase` + explicit
  `UseRouting` so the route-match happens against the prefix-stripped
  path; cookies and redirects reflect the original scheme.

### nginx (verified)

The nginx configuration below has been tested end-to-end by the author
behind a real TLS certificate and public hostname, including
WebAuthn/passkey flows from Android Credential Manager.

```nginx
# /etc/nginx/sites-available/totp
server {
    listen 443 ssl http2;
    server_name totp.example.com;

    ssl_certificate     /etc/letsencrypt/live/totp.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/totp.example.com/privkey.pem;

    # --- At-root deployment (BasePath="") ---
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host  $host;
    }
}
```

At-prefix deployment (`BasePath=/totp`):

```nginx
server {
    listen 443 ssl http2;
    server_name example.com;

    # other locations ...

    # IMPORTANT: no trailing slash on proxy_pass so the /totp prefix is
    # preserved when it reaches Kestrel.
    location /totp {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Android passkeys (Credential Manager) fetch assetlinks.json from the
    # apex of the domain, not from under the prefix. If you want passkey
    # sign-in from Android to work when PsTotp is under a sub-path, the
    # file has to be reachable at the domain root.
    location = /.well-known/assetlinks.json {
        proxy_pass http://127.0.0.1:5000/.well-known/assetlinks.json;
    }
}
```

**Trailing-slash trap**: `proxy_pass http://backend/` (with trailing
slash) strips the `/totp` prefix before sending to Kestrel, breaking
`UsePathBase`. Keep `proxy_pass http://backend;` (no trailing slash) so
Kestrel sees the full prefixed path. Don't be clever here.

Match the config to `Fido2:ServerDomain` + `Fido2:Origins` +
`AllowedOrigins`. If you're serving at `https://totp.example.com/totp/`,
then:

```json
{
  "BasePath": "/totp",
  "AllowedOrigins": "https://totp.example.com",
  "Fido2": {
    "ServerDomain": "totp.example.com",
    "Origins": [ "https://totp.example.com" ]
  },
  "ReverseProxy": {
    "KnownProxies": [ "127.0.0.1" ]
  }
}
```

### Caddy and Traefik (best-effort examples, unverified)

The author hasn't run PsTotp behind Caddy or Traefik. The snippets below
are reasonable starting points but have not been end-to-end tested —
especially WebAuthn and `BasePath` deployments. Verify carefully before
relying on them and please report corrections.

**Caddy**, at root, with automatic HTTPS:

```caddy
totp.example.com {
    reverse_proxy 127.0.0.1:5000 {
        header_up X-Forwarded-Proto {scheme}
    }
}
```

**Traefik** v3, as a docker-compose service alongside PsTotp:

```yaml
# sketch — not verified
services:
  app:
    image: pstotp:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.pstotp.rule=Host(`totp.example.com`)"
      - "traefik.http.routers.pstotp.tls=true"
      - "traefik.http.routers.pstotp.tls.certresolver=le"
      - "traefik.http.services.pstotp.loadbalancer.server.port=5000"
```

### HTTPS directly on the server (dev / LAN only)

```json
{ "EnableHttps": true }
```

enables a self-signed cert on port 5001. Good for testing against Android
Credential Manager on your LAN (Credential Manager requires HTTPS). **Not**
intended for internet-facing deployments — passkey RP validation gets
finicky with self-signed certs, and browsers will warn your users.

## Configuration and secrets

Configuration layers, later wins:

1. `appsettings.json` — shipped defaults, no secrets.
2. `appsettings.<Environment>.json` — shipped overlay per environment
   (`Development` is checked in; `Production` is yours to author).
3. `ConfigFile` / `PsTotpConfigFile` env var or `--config <path>` CLI arg
   — external file, merged on top of the built-ins.
4. Environment variables, using ASP.NET's `__` delimiter (e.g.
   `ConnectionStrings__PsTotpDb`, `Fido2__Origins__0`).

Secrets (`Jwt:Secret`, DB passwords) belong in:

- An environment variable on the service or container, or
- An external config file outside the repo, readable only by the service
  account, or
- Your secret manager of choice (Docker secrets, AWS SSM, Azure Key Vault, ...)
  sourced via environment variable.

Never put real secrets in a committed file. The values in the shipped
`docker-compose.yaml` and `appsettings.Development.json` exist purely so
the stack starts without setup and are not safe for any public-facing
deployment.

Connection strings are sanitised in startup logs — the credentials portion
is stripped before logging — but environment-variable dumps and process
listings are still a risk vector on shared hosts. Treat them accordingly.

## Backup and restore

PsTotp has three distinct backup levels. Pick the one that matches the
recovery scenario you actually have in mind — they are not
interchangeable.

### 1. Admin DB backup (cross-provider, recommended for deployment moves)

PsTotp ships an admin-only, DB-independent backup/restore path designed
specifically so you can move a deployment between providers (Postgres →
SQL Server, Docker → bare metal, etc.) without carrying database-engine
specifics along with it.

- **Export**: `POST /api/admin/backup` (admin auth, JSON body
  `{ "password": "..." }`) returns an encrypted JSON file containing
  every user, device, vault entry, vault-key envelope, recovery code,
  WebAuthn credential, and audit event on the server. Encryption is
  Argon2id-derived AES-GCM with the password you supply.
- **Restore**: `POST /api/admin/restore` (admin auth, multipart upload:
  `file` + `password` fields) decrypts the file, **wipes the existing
  database**, and repopulates it from the backup inside a single
  transaction. All transient state (login/registration/recovery sessions,
  refresh tokens, WebAuthn ceremonies) is cleared as part of the restore.

File format: `pstotp-admin-backup` (version 1). DB-independent by design
because it operates on the domain entities, not on SQL dumps. The same
file restores cleanly into any of the four supported providers.

**Who can use it.** Admin role is config-based. Add the email addresses
of your admin users to the `Admins` array in appsettings (or override
via environment variable):

```json
{
  "Admins": [ "you@example.com" ]
}
```

```bash
# docker-compose.yaml / systemd Environment= / Windows Environment
Admins__0=you@example.com
```

The role is applied to a user record on login, not on each request. If
you add someone to the list while they're already signed in, they won't
see admin UI until they sign out and back in.

**How to reach the UI.** Sign in to the web client as an admin →
**Settings → Admin** tab → scroll to the **Backup** panel at the
bottom. The Admin tab is hidden entirely for non-admin accounts. The
Android client does not currently expose this UI — admin-only endpoints
are web-only today.

**No scripted / scheduled backup today.** Login is a password-derived
verifier flow — the raw password never leaves the client, so you can't
authenticate admin requests with a `curl -d 'email=...&password=...'`
and there's no API-key or service-account endpoint yet. Admins are
expected to use the UI. If you need automated backups on a schedule,
fall back to system-level DB backup (see section 3 below) until a
proper machine-auth path lands — tracked in `memory/future_work.md`.

**Operational notes:**

- Treat the backup file and its password like DB credentials. The
  ciphertext is strong (Argon2id + AES-GCM) but everything in the
  payload is still the whole server's worth of data including the
  encrypted vault entries.
- Restore wipes and repopulates. There is no partial / merge mode.
- Plan to keep a rolling history of admin backups rather than overwriting
  one file — the format is versioned and future changes may need an older
  backup re-exported from the same server version.
- Admin backup captures **ciphertext only** — the vault entries remain
  end-to-end encrypted with each user's vault key. Restoring does not
  give the admin access to user secrets; users still need their own
  passwords / passkeys / recovery codes to unlock after restore.

This is the backup path to reach for when the question is "I want to
stand the service up somewhere else".

### 2. User vault export (single-user, cross-authenticator)

The in-app **Settings → Import & Export** flow lets an individual user
export their own vault in one of three formats (encrypted JSON, plain
JSON, or `otpauth://` URIs). Import accepts those plus Google
Authenticator migration URIs, Aegis plain JSON, and 2FAS JSON.

Scope:

- Contains **only the logged-in user's entries**, decrypted client-side
  into plaintext (or re-encrypted with a user-chosen password for the
  encrypted variant).
- Doesn't include devices, passkeys, recovery codes, admin state, or
  audit events.
- The right tool when the question is "I want to migrate to another
  authenticator app" or "keep a personal offline backup of my codes".

### 3. System-level database backup (operator responsibility)

For anything beyond the above — rolling nightly snapshots, point-in-time
recovery, replication — you're in database-engine territory. This guide
doesn't go there; consult the documentation for your chosen provider.
`pg_dump` / `pg_basebackup` for Postgres, backup plans / always-on
availability groups for SQL Server, `mysqldump` / binlog snapshots for
MySQL. If you're using docker-compose with the shipped `pg-data` volume,
make sure it's in whatever host-level backup scheme you already have
around the host.

The one exception worth writing down is **SQLite**, because its backup
is essentially a file copy:

- SQLite database file: `{DataDirectory}/pstotp.db`
- Rolling log files: `{DataDirectory}/logs/pstotp-*.log`
- Auto-generated JWT signing key (zero-config only): `{DataDirectory}/jwt-secret.key`

`{DataDirectory}` resolves in this order:

1. `PSTOTP_DATA` environment variable
2. `DataDirectory` config key
3. `%APPDATA%\pstotp` on Windows / `~/.pstotp` on Linux/macOS

To back up a SQLite deployment: stop the service, copy the whole data
directory to your backup location, restart. On restore, put the files
back into `{DataDirectory}` and start the service — no other steps are
needed.
