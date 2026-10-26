# iOS vs Android / web: intentional differences

Running list of places where the iOS client deliberately does something different from the Android
(and, where relevant, web) client. **Nothing here is decided yet** — we review the whole list at the end
and, for each row, either keep the iOS behaviour, port it back to Android/web, or change iOS to match.

Fill in the **Decision** column when we do. Add a row whenever a new difference is introduced.

Legend — **Kind**: `behaviour` (observable difference), `platform` (iOS can't / shouldn't do it the same way),
`internal` (same observable result, different implementation), `cosmetic`.

## Differences

| # | Area | Android / web | iOS | Why | Kind | Decision |
|---|------|---------------|-----|-----|------|----------|
| 1 | Secret validation on add/import | Manual form only checks non-empty; paste/QR don't validate. A bad secret can be saved, and `TotpCard` then throws while generating codes (see `docs/BUGS-TODO.md`). | Secret must decode as non-empty Base32 (`EntryValidation`) for manual, pasted and (later) scanned entries. The card also degrades to "Invalid secret" instead of failing. | Prevents unusable entries / a likely Android crash. | behaviour | |
| 2 | Account name on the card | Card shows issuer + code only. | Card also shows the account name as a caption. | Several accounts at one issuer are otherwise indistinguishable in the list. | behaviour | |
| 3 | Atomic multi-step writes | `setupPassword` writes salt/verifier/wrapped key/mode as four separate statements; `deleteEntry` / `reorderEntries` are not transactional. | Each is one DB transaction. | A crash mid-setup can leave a vault that reports set-up but can never unlock. | internal (fixes an Android bug) | |
| 4 | Google Authenticator migration URI | `URLDecoder` turns a literal `+` into a space, so base64 decoding fails. | `+` stays `+`; only `%XX` is decoded. | `+` is a valid base64 digit; Google's own export percent-encodes it, so this only affects hand-edited URIs. | behaviour | |
| 5 | Import of a bad `otpauth://` line | `importAutoDetect` lets the exception escape to the caller. | Returns `.error("Invalid otpauth URI: …")`. | One error path instead of two. | behaviour | |
| 6 | Exported JSON formatting | org.json `toString(2)` → `"key": value`. | Foundation pretty-printing → `"key" : value`, keys sorted. | Library formatting; both import fine on all clients. | cosmetic | |
| 7 | Clipboard clearing | Handler posts a clear after 30 s (only works while the process lives), marks the clip sensitive, toasts "Clipboard cleared". | Pasteboard item carries an `expirationDate` (system clears it even if the app is suspended) and is `localOnly` (kept off Universal Clipboard). No "cleared" toast. | iOS provides this natively and it is more reliable. | platform | |
| 8 | Screen-capture protection | `FLAG_SECURE` blocks screenshots, recents thumbnails and recording. | iOS cannot block screenshots. The app shows a privacy cover when not active (app-switcher snapshot) and while the screen is recorded / mirrored. | No platform equivalent of `FLAG_SECURE`. | platform | |
| 9 | Backup exclusion | `data_extraction_rules.xml` excludes everything from cloud backup and device transfer. | The `PsTotp` Application Support directory is flagged `isExcludedFromBackup`. | Same intent: keys/vault must not leave the device via backup. | platform | |
| 10 | Theming | Brand palette, or Material You dynamic colours (`use_system_colors` setting). | Brand palette only (light + dark); no dynamic-colour setting. | No iOS equivalent of Material You. | platform | |
| 11 | UI idioms | FAB to add, dropdown menus, Material dialogs, in-app search bar. | Toolbar add button, sheet, swipe-to-delete, system `.searchable`, system alerts, `PasteButton`. | Native iOS patterns. | platform | |
| 12 | Device / orientation | Phones and tablets, any orientation. | iPhone only, portrait only (for now). | Scope; revisit after the feature port. | platform | |
| 13 | Version numbers | `versionName` = `git describe --tags --dirty=-dirty` minus `v`; `versionCode` = 1. | Same label in `PsTotpVersionLabel`; `CFBundleShortVersionString` = numeric tag only; `CFBundleVersion` = commit count. | The App Store requires a numeric short version and an increasing build number. | platform | |
| 14 | Argon2 execution | Caller decides which dispatcher. | Setup/unlock run Argon2 on a detached task so the UI thread never blocks. | Responsiveness. | internal | |
| 15 | Local database | Room. | GRDB (same schema, v3 columns). | Native choice; schema is intentionally identical. | internal | |
| 16 | Scanner after a rejected code | Scanner stops permanently after the first detected `otpauth://` code, even when the app then rejects it (see `docs/BUGS-TODO.md`). | Keeps scanning; the same code is debounced for 2 s (`ScanDebouncer`), so a bad code shows its error without stranding the user. | Recovery without leaving the tab. | behaviour (fixes an Android bug) | |
| 17 | Photo with several QR codes | Only the first detected barcode is checked for `otpauth://`. | The first `otpauth://` code among all detected codes is used. | A non-account QR next to the account QR shouldn't hide it. | behaviour (fixes an Android bug) | |
| 18 | Camera permission denied | Shows "Camera permission required" with a Grant button that re-requests. | iOS only prompts once, so the denied state explains and offers "Open Settings". No-camera devices (simulator) get their own message. | Platform permission model. | platform | |
| 19 | QR display | `AlertDialog`, ZXing at the default error-correction level. | Sheet with a "keep it private" note; CoreImage at level M with a 4-module quiet zone, rendered with whole pixels per module. | Native presentation; the extra note is because the code reveals the secret. | cosmetic | |
| 20 | Photo picking | Photo picker via activity result. | System `PhotosPicker` (no photo-library permission needed); EXIF orientation honoured and huge photos bounded to 4096 px before decoding. | Platform picker; protects memory. | platform | |
| 21 | Saving an unchanged edit | Always re-encrypts and updates the entry, marking it pending sync when connected. | Does nothing when the trimmed values equal the current ones. | Avoids a pointless write and sync. | internal | |

## Same result, but written explicitly (not differences)

- **Entry ids are lowercase UUIDs** — Swift's `UUID().uuidString` is uppercase, so the repository lowercases it.
  The id is the AES-GCM associated data and the server GUID; Android and web generate lowercase.
- **Otpauth label rule** — `resolveLabel` / `resolveOtpauthLabel` are now identical on all three clients
  (commit `2cefecd`).
- **Scanning only accepts `otpauth://`** — same as Android; Google's `otpauth-migration://` QR codes are imported
  from a file / pasted URI, not scanned (logged as a gap in `docs/BUGS-TODO.md`).
- **Stable sort** — iOS breaks ties explicitly by incoming order; Kotlin's `sortedBy` is stable already.

## Not ported yet (pending, not differences)

icon editing (the Edit screen keeps the current icon; changing it comes with the icon picker), drag-to-reorder, settings (lock timeout, layout,
import/export UI, change password), biometric unlock, icon picker / icon library, "next code" preview,
connected mode (server sync, passkeys, devices, audit, recovery).
