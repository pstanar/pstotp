# PsTotp — Developer Guide

This is the guide for people working on PsTotp itself: setting up the repo,
running the stack, adding endpoints and migrations, running tests, and the
conventions we follow.

If you want an introduction to what PsTotp *is* and why it's shaped the way
it is, read `docs/architecture/PLAN.md` first — this file is the "how to
work on it" companion, not the "what is it" pitch.

## Audience

This guide is written for external contributors. There is one original
developer; everyone else comes in cold. Prerequisites:

- Comfortable with .NET 10, ASP.NET Core minimal APIs, and Entity Framework Core.
- Comfortable with React 19 + TypeScript (strict) and Vite.
- For Android work: comfortable with Kotlin, Jetpack Compose, and Gradle.
- Familiarity with symmetric/asymmetric crypto primitives (AES-GCM, HKDF,
  Argon2, ECDH, WebAuthn) is helpful but not required.

## Repository layout

```
/src                                .NET 10 server
  Server.Api                        Minimal-API entry point, endpoint classes
  Server.Application                Use cases, DTOs, service interfaces
  Server.Domain                     Domain entities + enums (no dependencies)
  Server.Infrastructure             EF Core, services, shared across DB providers
  Server.Infrastructure.Postgres    Postgres-specific migrations + design-time factory
  Server.Infrastructure.SqlServer   SQL Server-specific migrations + design-time factory
  Server.Infrastructure.MySql       MySQL-specific migrations + design-time factory
  Server.Infrastructure.Sqlite      SQLite-specific migrations + design-time factory

/tests/PsTotp.Tests                 MSTest server-side integration + unit tests

/client/web                         React + TypeScript web client (Vite)
/client/android                     Kotlin + Compose Android client
  app/                              UI + ViewModels
  core/                             crypto, DB, repository, sync, API client

/docs/architecture                  design docs (PLAN, threat model, key hierarchy, ...)
/docker-compose.yaml                Postgres + server container for local / prod use
/build.sh, /build.ps1               Cross-platform publish scripts
/Dockerfile                         Multi-stage build → self-contained server + SPA
/Dockerfile.build                   Container-based all-in-one build of every
                                    release artifact (archives + Android APK),
                                    for hosts that don't have the toolchains
/Dockerfile.build.dockerignore      Per-file ignore used only by Dockerfile.build
                                    so it can see .git + client/android
```

Project references go in one direction: Domain ← Application ← Infrastructure,
and Api references Application + Infrastructure + all migration assemblies.
Keep it that way — don't let Domain or Application depend on Infrastructure.

## Prerequisites

None of the IDEs below are required. Everything in this guide works with a
plain editor and command-line tools. If you use an IDE, common choices are:

- **Server**: Visual Studio 2026, JetBrains Rider, or VS Code with the C# Dev Kit.
- **Web**: JetBrains WebStorm or VS Code.
- **Android**: Android Studio.

Required tooling:

- **.NET SDK 10.0** or newer — `dotnet --version` should print 10.x.
- **Node.js 20 LTS** or newer (Vite 7, `@types/node ^24`).
- **JDK 17** for Android builds. The Gradle wrapper is committed, so Gradle
  itself doesn't need to be installed separately.
- **Android SDK** with platform 35 (target/compile) and platform-tools, plus
  NDK only if you plan to work on native code (we don't currently).
- **Git** for version control.

Optional tooling:

- **Docker** + **docker-compose** if you want the easy Postgres setup.
- **`dotnet-ef`** CLI tool for EF Core migrations (`dotnet tool install -g dotnet-ef`).
- **Postgres / SQL Server / MySQL** if you want to run against a native DB
  instead of Docker or the zero-config SQLite fallback.

## First-time setup

```bash
git clone <repo-url>
cd pstotp

# Server + tests (one-time restore)
dotnet restore PsTotp.slnx

# Web client
cd client/web
npm ci
cd ../..

# Android client (Gradle wrapper downloads itself on first invocation)
cd client/android
./gradlew help     # confirms the toolchain picks up the JDK
cd ../..
```

Nothing else is required before running. The server runs with zero config
against SQLite; the web dev server picks up the Vite CORS allowance from
`appsettings.Development.json`.

## Running the stack locally

The API server and the web client run in **separate terminals** — nothing
automates the pair today.

### Option A: Zero-config (single-user, SQLite)

Fastest path to a running system. Everything is created for you on first run.

```bash
# Terminal 1
dotnet run --project src/Server.Api/PsTotp.Server.Api.csproj
```

On startup you'll see it pick a data directory (`%APPDATA%\pstotp` on
Windows, `~/.pstotp` otherwise), auto-generate a JWT signing key, create the
SQLite database, log the bound address, and open a browser. The API listens
on `http://0.0.0.0:5000` by default.

If you only want to work on the server, you're done: hit `http://localhost:5000`.
If you want to work on the web client against a live backend, start it too:

```bash
# Terminal 2
cd client/web
npm run dev        # Vite on http://localhost:5173
```

The web client in dev mode targets `http://localhost:5000/api`. `AllowedOrigins`
in `appsettings.Development.json` already permits `http://localhost:5173`.

### Option B: Postgres (multi-user dev)

This is the author's default because it's the closest shape to production.

```bash
# Terminal 1: start Postgres in a throwaway container
docker compose up -d db

# Terminal 2: server, pointing at Postgres via Development config
ASPNETCORE_ENVIRONMENT=Development dotnet run --project src/Server.Api/PsTotp.Server.Api.csproj
# (on PowerShell: $env:ASPNETCORE_ENVIRONMENT='Development'; dotnet run ...)

# Terminal 3: web client
cd client/web && npm run dev
```

`appsettings.Development.json` defaults to a `Host=localhost;Database=pstotp;
Username=pstotp;Password=pstotp` connection string, which matches the
docker-compose `db` service. The server auto-applies migrations on startup
in Development.

If you prefer native Postgres or SQL Server, install it, create the database
manually, and override `ConnectionStrings:PsTotpDb` + optionally
`DatabaseProvider` via environment variables or a user-scoped config file —
see `docs/CONFIG.md` for the full list.

## Database providers and migrations

PsTotp supports PostgreSQL, SQL Server, MySQL, and SQLite. Each provider has
its own migrations assembly under `src/Server.Infrastructure.<Provider>/`
because the SQL dialects differ enough that shared migrations would fight
each other. The provider used at runtime is selected by the
`DatabaseProvider` config key.

### Adding a migration

When you change a domain entity, add a matching migration **to each
provider's migrations project**:

```bash
# Pick a provider, set DatabaseProvider to match, generate the migration
# targeting its Infrastructure project.
DatabaseProvider=PostgreSQL \
  dotnet ef migrations add <Name> \
  --project src/Server.Infrastructure.Postgres \
  --startup-project src/Server.Api

DatabaseProvider=SqlServer \
  dotnet ef migrations add <Name> \
  --project src/Server.Infrastructure.SqlServer \
  --startup-project src/Server.Api

DatabaseProvider=MySql \
  dotnet ef migrations add <Name> \
  --project src/Server.Infrastructure.MySql \
  --startup-project src/Server.Api

DatabaseProvider=SQLite \
  dotnet ef migrations add <Name> \
  --project src/Server.Infrastructure.Sqlite \
  --startup-project src/Server.Api
```

Use the same `<Name>` across all four so they line up. Review the generated
SQL for each provider — the same C# model change often produces
non-equivalent DDL across dialects, and you'll want to spot that before it
reaches a test run.

In Development the server applies migrations automatically on startup. In
production it applies them for SQLite (zero-config) but **not** for the
other providers — those are expected to be applied deliberately with
`dotnet ef database update` or an equivalent step in the deployment
pipeline.

## Adding an API endpoint

Endpoints are static methods on classes named `<Concern>Endpoints` in
`src/Server.Api/EndPoints/`, wired up from `Routes.cs`. The handler takes
its collaborators as parameters (dependency injection via the ASP.NET
minimal-API parameter binder), does its work, and returns an `IResult`.

> See [`docs/API.md`](API.md) for the external-facing narrative of the
> existing surface (auth flows, vault sync, error model, 409 recipe) and
> [`docs/openapi.json`](openapi.json) for the field-level schema. After
> you add or change an endpoint, `build.sh` / `build.ps1` will regen
> `openapi.json` and fail if you forgot to commit the update —
> if the shape changed for integrators, also update `API.md` by hand.

General shape:

```csharp
public static async Task<IResult> DoThing(
    ThingRequest request,
    AppDbContext db,
    IAuditService audit,
    HttpContext httpContext,
    ClaimsPrincipal user)
{
    // 1. Authorise. DeviceAuthHelper.GetUserId / GetDeviceId pull the
    //    identity from ClaimsPrincipal. Use its .Forbid() / .NotFound()
    //    helpers to fail fast.

    // 2. Validate input. Reject with Results.BadRequest / .Problem.

    // 3. Do the work. If multiple domain changes need to happen together,
    //    they all go through the same db.SaveChangesAsync() so audit
    //    events and domain changes commit as one unit.

    // 4. Audit. audit.Record(AuditEvents.X, ...) adds an event to the
    //    change tracker; it will be persisted by the endpoint's
    //    SaveChangesAsync. Don't call SaveChangesAsync on the audit
    //    service itself — that's the whole point.

    // 5. Return Results.Ok(new ResponseDto(...)). Prefer explicit DTOs
    //    over returning entities.
}
```

Conventions that have emerged from how existing endpoints evolved:

- Put auth-level route grouping in `Routes.cs`, not on the handler.
- Public endpoints that accept any input get `OriginValidationFilter` in
  the pipeline.
- DTOs live in `src/Server.Application/DTOs/`. Use `sealed record` for them.
- Binary fields go over the wire as standard base64 strings (not base64url).
  Decode/encode via `Convert.FromBase64String` / `Convert.ToBase64String`.
- Timestamps are ISO-8601 UTC. Don't introduce local times.
- `AuditEvents.cs` centralises the event-name constants. Add new ones there
  rather than string-literal-ing at the call site.
- Exceptions that escape reach the global `IExceptionHandler`, which renders
  them as RFC 7807 ProblemDetails. If you want to surface a user-facing
  message via `detail`, either throw an exception your handler maps, or
  return `Results.Problem(...)` explicitly.

Look at a similar existing endpoint (`AccountEndpoints`, `AuditEndpoints`,
`DeviceEndpoints`) before adding yours — the codebase has an established
shape and new endpoints should match.

## Tests

### Server

MSTest via `dotnet test`.

```bash
dotnet test PsTotp.slnx
```

Integration tests in `tests/PsTotp.Tests/Api/` spin up a `WebApplicationFactory`
backed by in-memory SQLite. They set `ASPNETCORE_ENVIRONMENT=Testing`, which
skips auto-migrate and the global exception handler so assertions see real
exceptions. Helpers in `tests/PsTotp.Tests/Infrastructure/` cover registering
a user, logging in, creating authenticated clients, and reaching into the
DbContext.

Add tests next to their peers. If you're adding a new endpoint, add an
`<Endpoint>Tests.cs` file that walks the happy path and the main failure
modes.

### Web

Vitest + Testing Library.

```bash
cd client/web
npm run test        # one-shot (CI flavour)
npm run test:watch  # watch mode
npm run lint        # eslint
npm run build       # tsc -b + vite build — use this to typecheck! (see below)
```

Pure logic (crypto helpers, parsers, hooks with no DOM deps) lives in
`src/tests/*.test.ts`. React components get tested via
`@testing-library/react` when there's meaningful behaviour — most presentational
components aren't unit-tested.

**Typecheck note**: `npx tsc --noEmit` at the root of `client/web` checks
nothing because the root `tsconfig.json` has `"files": []` and exists only
to dispatch to `tsconfig.app.json` + `tsconfig.node.json`. Use `npx tsc -b`
(build mode) or `npm run build` to get a real typecheck.

### Android

JUnit 4 tests in the `:core` module (pure JVM, no emulator required).

```bash
cd client/android
./gradlew :core:testDebugUnitTest
```

Android-framework-dependent tests go in `:core`'s `androidTest/` (run on an
emulator/device), but we try to keep heavy logic in `:core`'s pure Kotlin
code so that most testing is cheap. When a helper inside an Android class
needs coverage, extract the pure part into an internal top-level function
and test that — see `buildErrorMessage` in `ApiClient.kt` or
`isVaultKeyMismatch` in `VaultRepository.kt` for the pattern.

## Android build

From `client/android/`:

```bash
./gradlew :app:assembleDebug         # debug APK
./gradlew :app:compileDebugKotlin    # quick compile check
./gradlew :core:testDebugUnitTest    # :core unit tests
```

Android Studio is the most convenient IDE for UI work, but none of the
Gradle tasks require it — the wrapper pulls in Gradle on first run, and
any JDK 17+ on `PATH` (or `JAVA_HOME`) will do.

A signed release build (keystore configuration, AAB/APK distribution) is
not yet set up. See `memory/future_work.md` for the current plan.

## Conventions

Follow the patterns you see in the code. A handful of things worth calling
out because they're not obvious from any one file:

- **Keep commits focused.** Don't mix refactorings, whitespace/formatting
  changes, and logic changes in the same commit. Separate them so a
  reviewer can understand each independently.
- **Conventional-ish commits, but not dogmatic.** The existing log uses
  short imperative subjects (`Android: fix X`, `Web: add Y`) with a prefix
  pointing at the area. Match that shape.
- **Endpoints as static methods returning `IResult`**, not controllers. See
  the existing endpoint files.
- **Compose state hoisted up** (to ViewModels or screen composables), not
  buried in presentational components. Presentational components take
  their data as parameters.
- **No raw body text in exception messages.** If a response fails and the
  body isn't JSON, produce a status-code-based message — both `ApiClient`
  implementations have a dedicated helper for this. Otherwise a
  reverse-proxy HTML error page can end up rendered as an error string in
  the UI.
- **Don't silently swallow decryption failures.** Wrong-key symptoms must
  be loud — the `VaultKeyMismatchException` path exists precisely because
  an earlier "return what decrypted, drop the rest" approach hid a bug for
  weeks.
- **Don't let auth and vault state disagree.** The
  `AuthViewModel.tryUnlockThenConnect` pattern gates the transition to
  `Connected` on a successful vault unlock. Apply the same shape in any
  new connect-like flow.
- **Server is zero-knowledge.** Never add fields to `VaultEntry` (or any
  sync DTO) that would leak plaintext secrets or plaintext issuer/account
  names. If you think you need server-side search over vault contents,
  stop and reread `docs/architecture/threat-model.md`.

## Where to ask questions / file bugs

File a GitHub issue. Pull requests should:

- Build cleanly (server: `dotnet build PsTotp.slnx`; web: `npm run build`;
  Android: `./gradlew :app:compileDebugKotlin`).
- Pass tests (see the three sections above).
- Update or add tests for behavioural changes. Use the "pure helper"
  extraction pattern to avoid platform dependencies when you can.
- Not include unrelated formatting changes alongside the functional diff.
