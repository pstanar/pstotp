package io.github.pstanar.pstotp.core.repository

/**
 * Decide whether a batch of decrypt failures means the vault key is wrong
 * (caller should throw VaultKeyMismatchException and refuse to show an
 * empty vault) or is a sporadic per-entry failure (caller returns what it
 * could decrypt and moves on).
 *
 * Rule: tolerate exactly one failure as long as something decrypted.
 * Anything else — zero successes, or more than one failure — is treated
 * as a mismatch. Kept as a pure function so the edge cases are easy to
 * cover in tests.
 */
internal fun isVaultKeyMismatch(failures: Int, successes: Int): Boolean {
    if (failures <= 0) return false
    if (successes == 0) return true
    return failures > 1
}
