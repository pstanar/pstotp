# Contributing to PsTotp

Thanks for your interest. This is a small, single-author project; the
process below keeps it lightweight while avoiding the kinds of PRs that
are painful to review or land.

## Before you write code

**Open a GitHub issue first** for anything larger than a small fix —
bug reports, feature proposals, refactorings, anything that will touch
more than a handful of lines or more than one area (server / web /
Android). This is so we can align on the approach before you invest
time. Small self-evident fixes (typos, obvious bugs with an obvious
fix, doc tweaks) can go straight to a PR.

## Scope — what's off-limits without prior discussion

PsTotp has a few load-bearing decisions that shouldn't be revisited in
a drive-by PR. If your change touches any of these, raise it as an
issue first so we can talk it through:

- **The zero-knowledge contract.** The server must never see plaintext
  vault material. Don't add fields to `VaultEntry` (or any sync DTO)
  that would leak secrets or plaintext issuer / account names. If you
  think you need server-side search over vault contents, re-read
  `docs/architecture/threat-model.md` first.
- **Crypto primitives.** AES-256-GCM, Argon2id, HKDF, ECDH P-256, the
  per-scope AAD strings, and the key hierarchy in
  `docs/architecture/key-hierarchy.md` are not up for casual revision.
  Bug fixes are welcome; redesigns need a conversation.
- **UI framework choices.** React + TypeScript + Tailwind + shadcn on
  the web, Jetpack Compose on Android. No framework swaps, no parallel
  UI stacks.
- **New database providers.** Four are supported today
  (PostgreSQL / SQL Server / MySQL / SQLite). Adding a fifth is
  non-trivial maintenance (new migrations project, design-time
  factory, CI coverage) — issue first.
- **Telemetry.** PsTotp does not phone home. No analytics, no
  telemetry, no crash-reporting services. This is a deliberate
  property of the app.

## Setting up a development environment

See [`docs/DEVELOPER.md`](docs/DEVELOPER.md) — prerequisites,
first-time setup, running the stack, tests, and the fuller list of
code conventions live there.

## Commit style

Short imperative subjects, prefixed with the area:

```
Server: fix 409 on concurrent icon-library writes
Web: consolidate icon uploads through the library
Android: bump AGP + Gradle, clear deprecation warnings
Docs: clarify recovery-code release window
```

- Keep commits focused. Don't mix refactorings, whitespace / formatting
  changes, and logic changes in the same commit — split them so a
  reviewer can understand each independently.
- Write the body in the imperative mood and explain the *why*, not the
  *what*. The diff already shows what changed.
- **Signed commits are preferred, not required.** If you already have
  a GPG or SSH signing key set up, please use it (`git commit -S`, or
  `git config --global commit.gpgsign true`). Unsigned commits are
  accepted — this is a nudge, not a gate.

## PR checklist

Before pushing, make sure your branch:

- **Builds clean** on the area you touched:
  - Server: `dotnet build PsTotp.slnx`
  - Web: `npm run build` (in `client/web`)
  - Android: `./gradlew :app:compileDebugKotlin` (in `client/android`)
- **Passes tests**. See the three `## Tests` subsections of
  `DEVELOPER.md` for how to run each. Add or update tests for
  behavioural changes — use the "pure helper" extraction pattern to
  keep tests platform-free when you can.
- **Doesn't mix unrelated formatting changes** with the functional
  diff. If your editor reflowed a file, revert the drive-by edits.
- **Doesn't break the zero-knowledge contract** (see Scope above).

## Licensing

PsTotp is licensed under [Apache 2.0](LICENSE). By submitting a pull
request, you agree that your contribution is licensed under Apache 2.0
on the same terms — inbound = outbound, no CLA, no separate agreement.
If your commit includes code you didn't write, call that out in the PR
description and make sure its license is compatible with Apache 2.0.

## Where to ask questions / file bugs

[GitHub Issues](https://github.com/pstanar/pstotp/issues). No Discord,
no mailing list, no Discussions tab — issues keep the history
searchable in one place. That may change if volume warrants it.
