# PsTotp — Android client

Kotlin + Jetpack Compose Android client for PsTotp. Supports both
**standalone** (local-only, no server) and **connected** (server-synced,
multi-device with passkeys) modes.

This README covers the Android-specific build / test / run workflow.
For project-wide setup, overall architecture, and contribution
conventions, see **[docs/DEVELOPER.md](../../docs/DEVELOPER.md)**.

## Prerequisites

- **JDK 17.** `java --version` should print `17.x`. The Gradle wrapper is
  committed, so Gradle itself doesn't need to be installed separately.
- **Android SDK** with platform 35 (target/compile) and platform-tools.
  `ANDROID_HOME` / `ANDROID_SDK_ROOT` should point at the SDK, and
  `platform-tools/` should be on your `PATH` if you want to run `adb`
  directly.
- **Android Studio** (any recent version) is the most convenient IDE,
  but none of the Gradle tasks require it. Any editor + the wrapper is
  fine.

No NDK is needed — we don't ship native code.

## Module layout

```
client/android/
  app/                           UI, ViewModels, navigation, screens
    src/main/java/io/github/pstanar/pstotp/
      MainActivity.kt
      PsTotpApp.kt
      ui/
        AuthViewModel.kt
        VaultViewModel.kt
        components/              reusable Compose components (TotpCard, TotpGridDetail, …)
        nav/                     NavGraph
        screens/                 one file per screen
        theme/                   colors + typography
      util/                      biometric / lifecycle helpers
  core/                          Kotlin-only library — crypto, DB, repository, sync, API
    src/main/java/io/github/pstanar/pstotp/core/
      api/                       ApiClient, VaultApi, DevicesApi, WebAuthnApi
      crypto/                    AesGcm, Argon2, Hkdf, KeyDerivation, Ecdh, TotpGenerator
      db/                        Room entities + DAOs
      model/                     shared data classes, otpauth-uri parser, VaultExport, ExternalImports
      repository/                VaultRepository (encryption, persistence)
      sync/                      SyncService, AuthService
      util/                      IconFetch
    src/test/                    JUnit 4 tests — 12 files, pure JVM
```

The split keeps `:core` free of Android-framework dependencies so its
tests run on the pure JVM, which matters because that's where most of
the cryptography and protocol logic lives.

**Application ID / namespace:** `io.github.pstanar.pstotp` (GitHub
reverse-DNS; stable across releases).

## First-time setup

```bash
cd client/android
./gradlew help   # or `gradlew.bat help` on Windows — verifies the
                 # toolchain picks up the right JDK and downloads
                 # Gradle 9.3.x into ~/.gradle/ on first run.
```

The first `./gradlew` invocation downloads the Android Gradle Plugin,
Kotlin, Compose, Room KSP, and ~500 MB of dependencies. Subsequent
builds are cached.

## Build and run

### Debug builds (all we ship today)

```bash
./gradlew :app:assembleDebug              # build debug APK
./gradlew :app:installDebug               # build + install to the connected device
./gradlew :app:compileDebugKotlin         # quick compile check without packaging
```

The debug APK is signed with the Android Studio-generated debug
keystore at `~/.android/debug.keystore`. Same cert across all your
debug builds, same SHA-256 fingerprint — stable for WebAuthn dev
testing against your local server.

APK location: `app/build/outputs/apk/debug/app-debug.apk`.

### Release builds — not yet wired

A signed release build (keystore configuration, AAB/APK distribution,
R8 shrink / Proguard rules) is not yet set up. Tracked in
`memory/future_work.md` → **Signed Android release**. Until it lands,
distribute via debug APKs or build from source.

## Tests

### Core unit tests (pure JVM)

```bash
./gradlew :core:testDebugUnitTest
```

12 test files covering crypto primitives (AES-GCM, HKDF, Argon2,
key-derivation), TOTP generation against RFC 6238 vectors, protobuf
import parsers (Google Authenticator migration URIs), the vault-key
mismatch heuristic, and the server-response error-message translator.
No emulator required.

When adding Android-framework-dependent logic to `:app`, try to extract
the pure part into `:core` as an internal top-level function and test
that. See `buildErrorMessage` in `core/api/ApiClient.kt` or
`isVaultKeyMismatch` in `core/repository/VaultRepository.kt` for the
pattern.

### Android-instrumented tests

There aren't any today. Real instrumentation tests would need a
connected device or emulator via
`./gradlew :app:connectedDebugAndroidTest` or
`:core:connectedDebugAndroidTest`.

## Running against a local server

The Android client reaches the server over HTTP(S). A few Android-
specific gotchas:

- **Emulator can't use `localhost`.** The emulator's own loopback is
  not your host machine. Use `10.0.2.2` (Google's documented "special
  alias for the host" address) as the server URL host. On a physical
  device connected over Wi-Fi, use the host machine's LAN IP instead
  (`ipconfig` / `ifconfig`).
- **Server URL format.** In the Connect Server screen, enter the URL
  with `/api` on the end — e.g. `http://10.0.2.2:5000/api`. The Android
  `ApiClient` appends endpoint paths to that base.
- **`AllowedOrigins` on the server** must include whatever host the
  app will see. For emulator testing, that means
  `http://10.0.2.2:5000` in your `appsettings.Development.json`
  (alongside the Vite dev origin already there).
- **Android network-security-config.** Debug builds allow cleartext
  HTTP to private IP ranges (including `10.0.2.2`), so testing against
  your local dev server without TLS works out of the box. Production
  builds will want HTTPS.

## WebAuthn / passkey testing

Android's Credential Manager requires HTTPS for passkey ceremonies —
cleartext origins are rejected. Options for local testing:

- **Production-style host** with a real TLS cert (what the author uses).
  Easiest if you already run a reverse proxy with Let's Encrypt; point
  the Android app at `https://<your-host>/api` and everything works.
- **Self-signed cert via `EnableHttps=true`** on a LAN test box. Works
  on Android but validation can be finicky with Credential Manager —
  expect some fiddling.

Server-side prerequisites for passkey flows:

- `Fido2:ServerDomain` equals the bare hostname served to the client
  (e.g. `totp.example.com`, no scheme, no port).
- `Fido2:Origins` contains both the web origin AND any
  `android:apk-key-hash:<base64url>` origins for the builds you're
  testing. The server auto-generates the `android:apk-key-hash:…` form
  from `Android:PackageName` + `Android:CertFingerprints`, so just
  setting those two config keys is enough. Fingerprints from
  `./gradlew :app:signingReport` (look for the `debug` variant's SHA-256).
- `Android:PackageName = io.github.pstanar.pstotp`.
- `Android:CertFingerprints = [ "<debug-cert-SHA-256>" ]`. Release cert
  fingerprint goes here too once signing is wired — Credential Manager
  matches against whichever cert actually signed the installed APK.

For production, Digital Asset Links at
`https://<apex>/.well-known/assetlinks.json` must list the release-
keystore SHA-256 fingerprint alongside `io.github.pstanar.pstotp`.
Credential Manager fetches this from the apex domain, not from under
any `BasePath` prefix — if the server sits at `https://example.com/totp`
the proxy still has to serve `assetlinks.json` from the apex.

## Verified hardware / tooling

Passkeys have been exercised end-to-end with:

- **YubiKey 5 NFC** as the FIDO2 authenticator.
- **Android Credential Manager** 1.5.x (`androidx.credentials:credentials:1.5.0`
  + `play-services-auth:1.5.0`).
- A production-style nginx + Let's Encrypt deployment with the server
  under a `/totp` path prefix.

Emulator + Google's built-in screen-lock credentials should also work
for basic passkey tests, but the author does live testing with the
YubiKey.

## Keeping `:core` and `:app` clean

- **Framework dependencies** (Activity, Compose, Android SDK APIs) go
  in `:app`. `:core` is Kotlin + Java stdlib + OkHttp + Room + org.json
  only; that's why its unit tests run on the pure JVM.
- **Shared data classes** (DTOs, entity shapes, enums) live in
  `:core/model/`. Don't duplicate them in `:app`.
- **ViewModels** live in `:app/ui/`, not `:core`. They hold StateFlow
  state that Compose observes.

## Troubleshooting

If the build fails on a fresh clone, check in order:

1. `java --version` reports 17.x (not 21, not 11). AGP 9.x requires 17.
2. `./gradlew --version` completes — that means the wrapper downloaded
   Gradle successfully. If it fails, check your corporate proxy settings.
3. Android SDK platform 35 is installed. Android Studio can install it
   via SDK Manager; the CLI equivalent is
   `sdkmanager "platforms;android-35"`.
4. For passkey-related failures, see
   [docs/TROUBLESHOOTING.md](../../docs/TROUBLESHOOTING.md) →
   *Android passkey: "No passkeys available"* and the neighbouring
   entries. The RP ID / origin / cert fingerprint chain is fiddly;
   that doc walks through the likely causes.
