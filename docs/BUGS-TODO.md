# Bugs & gaps found while porting to iOS

Collected while reading the server / web / Android code for the iOS port. Fix as a batch.
**Verified** = reproduced or proven by running code; **Suspected** = from reading only, confirm before fixing.

## Open

### Android

- [ ] **Invalid secret crashes the card (Suspected, likely)** — `TotpCard.kt:60` calls `TotpGenerator.generate`
  inside a `LaunchedEffect` with no `try`; `Base32.decode` throws `IllegalArgumentException` on a bad
  character. The manual form (`AddAccountTabs.kt`) only checks the secret is non-empty, and the paste/QR
  paths don't validate it either, so an entry with a bad secret can be saved and then crash the list on
  every render. Fix: validate Base32 at add/import time and make the card tolerate a failure.
  (iOS already does both: `EntryValidation`.)
- [ ] **`setupPassword` is not atomic** — `VaultRepository.setupPassword` writes salt, verifier, wrapped key
  and mode as four separate `settingsDao.set` calls. `isSetUp()` keys off the verifier, so a crash after
  the verifier but before the wrapped key leaves a vault that reports itself set up but can never unlock.
  Fix: wrap in `db.withTransaction`. (Fixed on iOS.)
- [ ] **`reorderEntries` / `deleteEntry` not transactional** — N separate `updateSortOrder` statements; a crash
  mid-loop leaves a half-applied order. Low severity.
- [ ] **Google migration URI: `+` becomes a space** — `ExternalImports.tryParseGoogleAuthMigration` runs the
  `data=` value through `URLDecoder.decode`, which turns a literal `+` (a valid base64 digit) into a space,
  so base64 decoding fails. Google's own export percent-encodes `+`, so this only bites hand-edited or
  re-encoded URIs. Low severity. (iOS keeps `+` as `+`.)
- [ ] **Test gap: crypto tests don't prove interop** — most of `core/src/test/.../crypto` only assert sizes and
  determinism (`HkdfTest`, `KeyDerivationTest`, `ClientProofTest`, `EcdhTest`). A drifting KDF or HKDF
  context string would still pass. The iOS package has known-answer vectors (RFC 6238/5869, Argon2id, web
  export format) in `client/ios/PsTotpCore/Tests/PsTotpCoreTests/Vectors/` that could be reused.
- [ ] **Test gap: `OtpauthUri.parse` has no tests** — it depends on `android.net.Uri`, so it can't run as a pure-JVM
  test. Only `resolveLabel` is covered (`OtpauthUriLabelTest`), and that test was **never run** (no JDK on the
  machine it was written on) — run `./gradlew :core:test`.
- [ ] **Reordering while a search is active pushes hidden entries to the end (Suspected)** — `VaultScreen` hands
  `reorderEntries` only the *filtered* ids, and `VaultViewModel.reorderEntries` sorts the full list with
  `positionMap[it.id] ?: Int.MAX_VALUE`, so every entry the filter hid is moved after the visible ones (the
  comment says it avoids "dropping" hidden entries, but it relocates them). Fix: write the visible ids back
  into the slots the visible entries occupied (iOS: `EntryListing.reordered`). Also: `moveEntry(id, direction)`
  in the ViewModel is not called from anywhere (dead code, or a missing accessibility alternative to dragging).
- [ ] **QR scanner stops for good after one rejected code (Suspected)** — `QrScanner.kt` sets `detected` with
  `compareAndSet(false, true)` before calling `onResult`, and never resets it. If the code is then rejected
  (an HOTP `otpauth://hotp/…`, a bad secret, an unsupported algorithm) the error is shown but the analyzer
  ignores every later frame until the user leaves and re-enters the tab. Fix: reset `detected` on failure
  (or debounce like iOS's `ScanDebouncer`).
- [ ] **Photo import only inspects the first barcode (Suspected)** — `ImagePickTab` takes
  `barcodes.firstNotNullOfOrNull { it.rawValue }` and only then checks for `otpauth://`, so an image whose first
  detected code is something else (a URL QR next to the account QR) reports "No QR code found in image".
  Fix: pick the first barcode whose value starts with `otpauth://`.
- [ ] **Gap: scanning ignores Google's `otpauth-migration://` QR codes** — file/URI import supports them
  (`ExternalImports.tryParseGoogleAuthMigration`) but both the camera and image paths drop anything not starting
  with `otpauth://`. Users exporting from Google Authenticator get a QR code, not a file. Enhancement, all clients.
- [ ] **Card doesn't show the account name (UX)** — `TotpCard` shows only the issuer, so several accounts at one
  issuer are indistinguishable in the list. (iOS shows the account name as a caption.)

### Web client

- [ ] **`parseOtpauthUri` accepts `NaN` digits/period (Verified)** — `totp.ts` uses `parseInt` and then
  `digits < 4 || digits > 10` / `period <= 0`; every comparison with `NaN` is false, so
  `otpauth://…?digits=abc&period=x` passes validation and yields `NaN` values.
  Fix: reject with `Number.isNaN` / `Number.isInteger`.
- [ ] **3 failing tests in `src/tests/WebLockNowAction.test.tsx` (Verified)** — `TypeError: Cannot read properties
  of undefined (reading 'setItem')`; `localStorage` is undefined in the test environment under Node 26.
  Fails with and without unrelated changes. Fix the vitest environment / storage stub.
- [ ] **Blank-vs-missing issuer differs from Android (resolved by the label fix, keep in mind)** — web already
  treated `issuer=` as absent; Android used the empty string. Both now follow `resolveLabel`.

### Server

- _None found yet — the server code hasn't been read closely. Add findings here._

## Done

- [x] **Colon in account name corrupted on otpauth export → import** (Android, web, iOS) — fixed in `2cefecd`.
  Known remaining edge: an account containing `:` with an *empty* issuer is still split, because the URI has
  no `issuer` param to anchor on (fix by having the exporter always emit `issuer=` when the account
  contains a colon).
