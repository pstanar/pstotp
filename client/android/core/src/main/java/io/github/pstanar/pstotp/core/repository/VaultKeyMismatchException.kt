package io.github.pstanar.pstotp.core.repository

/**
 * Thrown by VaultRepository.getAllEntries when the supplied vault key
 * decrypts a majority of stored entries to junk. Almost always indicates
 * the vault key in memory doesn't match the one entries were encrypted
 * with — surfacing it as an exception prevents the UI from silently
 * presenting an empty vault.
 */
class VaultKeyMismatchException(val failed: Int, val total: Int) :
    RuntimeException("Vault key mismatch: $failed of $total entries failed to decrypt")
