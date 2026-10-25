# CArgon2

Vendored copy of the Argon2 reference implementation (https://github.com/P-H-C/phc-winner-argon2),
dual-licensed CC0 1.0 / Apache 2.0 — see `LICENSE`.

Portable `ref.c` fill-segment only (no x86 `opt.c`, CLI, benchmarks or test harnesses), so it builds
on arm64 and x86_64 alike. Source files are unmodified from the upstream tree as packaged in
Argon2Swift 1.0.1 (tmthecoder/Argon2Swift @ 23e1bf5), which was the vendoring source only; it is
not a dependency.

Swift access goes through `Sources/PsTotpCore/Crypto/Argon2.swift`; correctness is pinned by the
known-answer vectors in `Tests/PsTotpCoreTests/Vectors/crypto-vectors.json`.
