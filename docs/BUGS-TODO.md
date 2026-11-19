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
- [ ] **Imported entries aren't validated; `period: 0` likely crashes the list (Suspected)** — Aegis / 2FAS /
  pstotp-plain / encrypted imports take `digits`, `period` and `algorithm` straight from the file.
  `TotpGenerator.generate` does `timestampSeconds / period` (and `timeRemaining` does `now % period`), which
  throws `ArithmeticException` for 0, on every render of that card. Fix: validate every imported entry like
  a manual one. (iOS: `VaultExport` runs `EntryValidation.validated` on each entry, and the generator
  throws instead of trapping.)
- [ ] **`setupPassword` is not atomic** — `VaultRepository.setupPassword` writes salt, verifier, wrapped key
  and mode as four separate `settingsDao.set` calls. `isSetUp()` keys off the verifier, so a crash after
  the verifier but before the wrapped key leaves a vault that reports itself set up but can never unlock.
  Fix: wrap in `db.withTransaction`. (Fixed on iOS.)
- [ ] **`reorderEntries` / `deleteEntry` not transactional** — N separate `updateSortOrder` statements; a crash
  mid-loop leaves a half-applied order. Low severity.
- [ ] **File import is not transactional** (Verified by reading) — `VaultViewModel.confirmImport` calls
  `updateEntry` / `addEntry` once per candidate; an exception part-way leaves some accounts imported and
  shows only "Import failed". Low severity. Fix: one transaction for the whole import. (Done on iOS:
  `VaultRepository.importEntries`.)
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
- [ ] **Connecting a device with local accounts leaves them under the wrong key (Suspected, likely)** — `AuthService.login`
  / `register` replace the local vault key with the account's (`persistPasswordEnvelope`) but never re-encrypt the
  existing local entries or the icon library; `login`'s `localVaultKey` parameter is unused. `unlockWithKey` then
  fails the mismatch check (more than one entry) and logs out, and `SyncService` assumes one key for every device
  ("no re-encryption is needed"). Fix: re-encrypt entries + icon library from the old key to the new one in one
  transaction when adopting the key. (iOS: `VaultRepository.replaceVaultKey`.) Confirm by registering on a device
  that already holds two or more accounts.
- [ ] **Offline deletions come back (Suspected, likely)** — `SyncService.pushEntry` hard-deletes the local tombstone
  in a `catch (_: Exception)` that also swallows network errors, so a deletion made offline never reaches the server
  and the entry reappears at the next pull. Fix: hard-delete only on success or a 404. (iOS does.)
- [ ] **A reorder on one device never reaches the others (Suspected)** — the server's `/vault/reorder` changes
  `SortOrder` but not `EntryVersion`, and `pullVault` applies a server entry's sort order only when its version is
  newer. Fix: also apply the sort order for entries with no pending local change. (iOS does.)
- [ ] **An edit made during a push is marked synced (Suspected)** — `pushEntry` calls `markSynced` (clears
  `pendingSync`) after the request returns, even if the entry changed meanwhile; the newer edit is never pushed.
  Fix: clear the flag only if the payload is unchanged. (iOS does.)

- [ ] **Offline unlock breaks if the account's KDF isn't the default (Suspected, likely)** — the server stores
  whatever KDF parameters the registering client sends (`RegistrationEndpoints.cs:162`, `AccountEndpoints.cs:50`;
  no validation) and returns them at login. `AuthService.login` derives `authKey` with those parameters and passes it
  to `persistPasswordEnvelope`, which stores the local verifier and wrapped vault key from it. Offline unlock
  (`KeyDerivation.derivePasswordAuthKey` → `Argon2.hash(password, salt)`) always uses the pinned 64 MB / t=3 / p=4,
  so for an account with other parameters (above the 32 MB / 2 / 1 floor) it derives a different key: "Incorrect
  password" at the lock screen, and Connect needs an unlocked vault, so no way back in. All three clients
  currently register with 64/3/4, so this needs a modified client or server. Same code path:
  `passkeyUnlockWithPassword`, `changePassword` (derives new material with the default, fine), recovery.
  Fix: in `login` / `passkeyUnlockWithPassword`, when `kdf != default`, derive a second `authKey` with the pinned
  parameters (same salt) for `persistPasswordEnvelope`; keep the server-parameter key for the proof and envelope
  decryption. (iOS: `AuthService.login`, `KdfConfig.isPinnedDefault`; test
  `loginWithPasswordEnvelopeAdoptsTheServerVaultKey`.) The passkey path doesn't exist on iOS yet: apply the same
  rule when it is ported.

- [ ] **First connect overwrites the account's icon library (Suspected, likely)** — `save()` sets
  `ICON_LIBRARY_DIRTY` on every local change, including in standalone mode, so a device with its own custom icons is
  dirty when it first connects. `refreshIconLibraryFromServer` runs `pushIfDirty` before `pullFromServer`; with
  expected version 0 the server answers 409 if the account has a library, and `pushCiphertext` handles that by
  refetching the version and putting again — the device's copy replaces the account's, so icons added on other
  devices are lost. Related: the local blob is still encrypted with the old local vault key (see the "wrong key"
  entry above), so what is pushed may be unreadable on every other device. Fix: when the device has never synced
  the library (`ICON_LIBRARY_SERVER_VERSION` is 0) and the server has one, merge instead (server icons plus local
  ones that match neither by id nor by `dataHash`/`sourceHash`, within the count and byte caps) and push the result.
  Also clear `ICON_LIBRARY_SERVER_VERSION` on logout so the next account counts as never synced. Same for the web
  client if it keeps a local copy. (iOS: `IconLibrarySyncService`, `IconDedup.merge`.)

- [ ] **Gap: no way to revoke a device from Android** — `DevicesApi.revokeDevice` exists but `DevicesScreen` only
  offers Approve / Reject on pending devices, so a lost phone can't be signed out from another phone (the web
  client has a Revoke button). Also nothing marks which entry is the current device. Enhancement. (iOS: Revoke
  with a confirmation on approved devices other than this one, and a "This device" label from the stored
  device id.)

- [ ] **Regenerating recovery codes never checks the password (Suspected, likely)** — `AuthService.regenerateRecoveryCodes`
  derives `authKey` from whatever password was typed and wraps the vault key under
  `deriveRecoveryUnlockKey(authKey)`; nothing compares it with the local verifier, and the request carries no
  proof. A typo gives new codes whose recovery envelope can never be opened (recovery derives the key from the real
  password), so the user believes they have working codes. Fix: verify the password first
  (`repository.unlockVault(password) != null`), or complete a step-up proof like the web client does. The web client
  is not affected: `recovery-management.tsx` does a throwaway login (`completeLogin`) first, which the server
  verifies. (iOS: checks against the vault's own verifier first.)

- [ ] **Account recovery can't survive its own hold period (Suspected, likely)** — the server holds recovery material
  for `Recovery:HoldPeriodHours` (default 24) and keeps the session for 72 h, and `RedeemCode` answers 409 while a
  session is active. `RecoveryScreen` keeps `sessionId` and the rest in `remember` state only, so leaving the screen
  (back, process death, rotation) loses the session: the user can neither resume it nor redeem a new code until the
  72 h expiry. Fix: persist the pending session (id, server URL, email, release time — no secrets) and offer
  "resume" on the connect screen; the password is only needed again at the final step. (iOS: `PendingRecovery` in
  settings, `RecoveryView` resumes.)
- [ ] **Recovery leaves a stale biometric key on a device with its own vault (Suspected)** — `completeRecovery` ends with
  `persistPasswordEnvelope(..., clearBiometric = false)` on the reasoning that recovery "decrypts the same vault key".
  That holds for the account's key, not for a freshly installed device that already set up a local vault under a
  different key: the biometric copy still wraps the local key, so biometric unlock yields the wrong key and entries
  fail to decrypt (same class as the connect/login case above). Fix: clear biometric unless the recovered key equals
  the current local key. The local entries are not re-encrypted either (see the connect entry). (iOS: through
  `adopt`, which does both.)

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
- [ ] **8 open Dependabot alerts on `main` (Verified, 2026-10-25)** — all in `client/web/package-lock.json`, all
  dev/build-time packages (dev server, test runner, browser-target data), none in the shipped bundle's runtime.
  Fix: bump to the patched versions below, re-run `npm test` and the build, and let Dependabot close the alerts.
  - High: `vite` → 8.1.6 (#36, GHSA-587h-7wmj-h5pm, launch-editor existence-check bypass on Windows);
    `source-map-js` → 1.2.2 (#34, GHSA-68fv-2mgg-jv7q, event-loop DoS); `browserslist` → 4.28.7
    (#29, GHSA-73wf-gq98-2v4g, crash / prototype write via custom stats file)
  - Moderate: `vite` → 8.1.6 (#37, GHSA-r825-w8mm-5pxw; #35, GHSA-698v-4r3x-3vcv, both launch-editor);
    `vitest` and `@vitest/mocker` → 4.1.11 (#31, #30, GHSA-82fw-gwwq-j7x9, file read via redirect mock);
    `baseline-browser-mapping` → 2.11.0 (#32, GHSA-w5vr-8v7q-w6rv, DoS on invalid input)

- [ ] **No floor on server-supplied KDF parameters (Suspected)** — `derivePasswordAuthKey` runs Argon2id with
  whatever `challenge.kdf` the server returns (login, recovery, step-up, change password). A hostile or compromised
  server could return e.g. 1 MB / 1 iteration and then brute-force the captured proof offline. Android and iOS
  reject anything below 32 MB / 2 iterations / 1 lane (`Argon2.hash` with the floors). Fix: same minimums in
  `derivePasswordAuthKey`, with a clear error. (Not affected by the offline-unlock issue above: the web client
  keeps no local password envelope and uses the server's parameters in every flow.)

### Server

- [ ] **Design question: regenerating recovery codes needs no proof of the password** — `RegenerateCodes`
  (`RecoveryManagementEndpoints.cs`) accepts any request from an approved device's token. Password change
  (`AccountEndpoints.cs`) requires a step-up `VerifierProof`; this endpoint doesn't, so the password check is
  voluntary client behaviour (web does a throwaway `completeLogin`, which also issues unused tokens and logs a
  login event; Android skips the check, iOS checks locally). Someone holding a stolen access token can
  retire the user's real recovery codes and install an envelope nobody can open, silently breaking recovery (not a
  takeover: recovery itself needs the password proof). Suggested: take a `VerifierProof` in
  `RecoveryCodeRegenerateRequest` and verify it as password change does; the proof and the envelope key come from
  the same derived key, so a typo then becomes impossible, and the web workaround can go. Hardening, not a defect
  in existing behaviour.
- [ ] **Gap: no `apple-app-site-association` endpoint (iOS passkeys)** — `MapWellKnownEndpoints` serves
  `/.well-known/assetlinks.json` (from `Android:PackageName` / `Android:CertFingerprints`) but nothing for iOS.
  Native iOS passkeys need `https://<rp domain>/.well-known/apple-app-site-association` listing
  `webcredentials.apps: ["<TeamID>.<bundle id>"]`, plus an Associated Domains entitlement in the app for that
  domain. Only needed if iOS passkey add/sign-in is ever implemented (deferred, see `client/ios/DIFFERENCES.md`).
  Suggested config: `Apple:AppIds`. Also confirm the server accepts the origin an iOS native passkey reports
  (`https://<rp id>`) against `Fido2:Origins`.

## Done

- [x] **Colon in account name corrupted on otpauth export → import** (Android, web, iOS) — fixed in `2cefecd`.
  Known remaining edge: an account containing `:` with an *empty* issuer is still split, because the URI has
  no `issuer` param to anchor on (fix by having the exporter always emit `issuer=` when the account
  contains a colon).
  Behaviour change to be aware of: a label whose prefix is *not* the `issuer` param is now kept whole
  (`otpauth://totp/Old:alice?issuer=New` → account `Old:alice`; previously `alice`).
