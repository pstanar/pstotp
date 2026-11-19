# PsTotp — iOS client

Native SwiftUI client (iOS 17+, iPhone, portrait). It does everything the Android client does, in standalone
and connected mode, except **adding a passkey and signing in with one** (see below). See
[`DIFFERENCES.md`](DIFFERENCES.md) for where it intentionally differs from Android/web, and
[`../../docs/BUGS-TODO.md`](../../docs/BUGS-TODO.md) for bugs found in the other clients along the way.

**Status:** feature-complete apart from the passkey ceremony; developed and tested on the simulator only.
Nothing has been run on a physical iPhone or against a production server yet — see
[Verify on a physical device](#verify-on-a-physical-device).

| Area | What is there |
|------|---------------|
| Vault | Set-up, unlock (password, Face ID / Touch ID), auto-lock, live codes with rings, list and grid layouts, search, sort modes, drag-to-reorder, add (manual, `otpauth://`, QR scan, photo), edit, delete, Show QR Code, "Show upcoming code" |
| Icons | Service icons, emoji, uploads and URLs; the "My icons" library |
| Import / export | Google Authenticator, Aegis, 2FAS, PsTotp (plain and encrypted JSON) |
| Connected mode | Create account, sign in, sign out, vault sync, My icons sync, Change Password, Devices (approve, reject, revoke), Audit Log, Recovery Codes, passkey management (list, rename, revoke), account recovery |

## Not available yet

- **Adding a passkey and signing in with a passkey.** Native iOS passkeys need an Associated Domains
  entitlement for each server domain compiled into the app (a generic build can't serve arbitrary self-hosted
  servers), a paid Apple Developer team, and an `apple-app-site-association` file on the server, which the
  server doesn't serve yet. Passkeys can be added from the web or Android client and then managed here.
  Account recovery stops with a message if the server requires a passkey step-up. Details in
  `DIFFERENCES.md` ("Not ported yet") and `docs/BUGS-TODO.md` (Server).
- **iPad and landscape**, and **plain `http://` servers** (App Transport Security blocks them; there is no
  exception in `Info.plist`). Use `https://`.

## Connecting to a server

Settings → Server Sync → **Connect to Server**. The address can be a bare host (`totp.example.com`), which gets
`https://` and the server's `/api` path, or the full API URL (`https://totp.example.com/api`). The vault must be
unlocked: connecting replaces the local vault key with the account's and re-encrypts the accounts already on
the device. From there you can sign in, create an account, or recover one. Sync runs after connecting, after
unlocking and after every change; **Sync Now** is in Settings.

## Layout

```
client/ios/
  project.yml            XcodeGen definition (the Xcode project is generated, not committed)
  scripts/set-version.sh derives the app version from git, like Android's build.gradle.kts
  DIFFERENCES.md         intentional differences from Android / web, with decisions
  PsTotp/                the app: SwiftUI views, AppModel, Keychain stores
  PsTotpTests/           app-level unit tests (AppModel, with a scripted server)
  PsTotpUITests/         end-to-end UI tests + opt-in screenshot capture
  PsTotpCore/            Swift package, no UI:
    Sources/PsTotpCore/
      Crypto/            Argon2id, HKDF, AES-GCM, ECDH device envelopes, client proof, TOTP
      Model/             entries, otpauth URIs, import / export, sorting, validation
      Persistence/       GRDB database, records, settings keys
      Repository/        VaultRepository (entries, settings, key replacement)
      Api/               ApiClient (tokens, refresh) and the server's request / response types
      Auth/              AuthService (login, register, recovery, password change), URL clean-up
      Sync/              SyncService (vault)
      Icons/             icon library, de-duplication, library sync
      Devices/ Audit/    device list logic, audit and server-time formatting
      QR/                QR decoding
```

`PsTotpCore` is the counterpart of Android's `:core` module. It has no UI dependencies, so its tests run on
the host in seconds, and anything that can be pure logic lives there. The app target stays thin.

## Prerequisites

- **Xcode 26+** (full Xcode, not just the Command Line Tools; developed on Xcode 27), with an iOS 17+ simulator
  runtime (`xcodebuild -downloadPlatform iOS`).
- **XcodeGen**: `brew install xcodegen`.
- **Node.js** only to regenerate the crypto test vectors (see below).
- An Apple Developer account is only needed for a physical device / TestFlight; simulator builds need none.
  The iOS client is not part of `build.sh` or CI.

## Build & test

```sh
cd client/ios

# Core package (fast, runs on the Mac)
(cd PsTotpCore && swift test)

# App
xcodegen generate                      # regenerates PsTotp.xcodeproj from project.yml
open PsTotp.xcodeproj                  # or build from the command line:
xcodebuild test -project PsTotp.xcodeproj -scheme PsTotp \
  -destination 'platform=iOS Simulator,name=iPhone 17'  # any installed iPhone (xcrun simctl list devices)
```

Run `-only-testing:PsTotpTests` for the quick unit tests (about a minute with the build); the UI tests
drive the real app and take about ten minutes for the whole suite. At the time of writing: 284 package tests,
93 unit tests and 23 UI tests (4 of them skipped unless opted into: two live-network tests need
`TEST_RUNNER_PSTOTP_LIVE=1`, two screenshot tests need `TEST_RUNNER_PSTOTP_SHOTS`). If the UI-test run sits forever with a blank white simulator screen, the test runner
failed to attach (the app's main thread is parked in `_dyld_start`): kill `xcodebuild`, shut the
simulator down, and run again.

### Screenshots for visual review

```sh
TEST_RUNNER_PSTOTP_SHOTS=/tmp/pstotp-shots xcodebuild test -project PsTotp.xcodeproj -scheme PsTotp \
  -only-testing:PsTotpUITests/ScreenshotTests -destination 'platform=iOS Simulator,name=iPhone 17'  # any installed iPhone (xcrun simctl list devices)
```

For the dark set, switch the simulator first (`xcrun simctl ui booted appearance dark`, and back to
`light` afterwards) — the `-AppleInterfaceStyle` launch argument does not change SwiftUI's colour scheme.

### Test hook

`-uitest-inmemory` makes the app use a throwaway in-memory database and in-memory secrets (a fresh, un-set-up
vault each launch, nothing in the Keychain). It exists for the UI tests; it cannot reach a real vault.

### What the tests don't cover

The UI tests can't reach anything behind a server connection, so connected mode is covered by unit tests
against scripted and fake servers (`ScriptedTransport`, `FakeVaultServer`, `FakeIconLibraryServer`) that follow
the real server's rules, and by the connect / register / recovery screens' error paths. Camera scanning, the
real Face ID sensor and passkeys can't run on the simulator.

## Crypto test vectors

`PsTotpCore/Tests/PsTotpCoreTests/Vectors/crypto-vectors.json` is generated by `generate.mjs` from Node's
built-in crypto (RFC 6238 / 5869 vectors, Argon2id, and the web client's export / storage formats):

```sh
node PsTotpCore/Tests/PsTotpCoreTests/Vectors/generate.mjs > PsTotpCore/Tests/PsTotpCoreTests/Vectors/crypto-vectors.json
```

## Verify on a physical device

Everything here passed only on the simulator or against a fake server. Before relying on the app, check on an
iPhone, ideally against a test server:

1. **Camera scan** of an `otpauth://` QR code (the simulator has no camera), including denying the permission
   and then allowing it in Settings.
2. **Face ID / Touch ID**: enable it, lock, unlock. Then change the enrolled faces or fingers and confirm
   biometric unlock is turned off with a message and the password still works.
3. **A real server**: create an account, sign out, sign in. Add, edit, delete and reorder an account and
   confirm it reaches the web or Android client, and the other way round.
4. **Two devices**: sign in on a second client, approve it from the iPhone (Settings → Devices), then revoke it.
5. **Change Password** on the iPhone: another client must sign in again, and the iPhone must still unlock
   offline with the new password.
6. **Recovery**: against a server with a short `Recovery:HoldPeriodHours`, run account recovery from a fresh
   install, leave the app during the hold, come back and resume.
7. **My icons**: add an icon on one client and confirm it appears on the other. Connect a device that has its
   own icons to an account that has some, and confirm neither side lost any.
8. **Backgrounding**: the app switcher shows the privacy cover, not codes; auto-lock follows the setting.
9. **Passkeys**: rename and revoke a passkey that was created on the web.
10. **A server over `http://`** is expected to fail (App Transport Security) with a clear network error.

## Versioning

`scripts/set-version.sh` runs after every build and stamps the app from `git describe --tags --dirty=-dirty`:
`PsTotpVersionLabel` is the full label (identical to Android's `versionName`), `CFBundleShortVersionString`
the numeric tag, `CFBundleVersion` the commit count.
