package io.github.pstanar.pstotp.core.repository

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VaultKeyMismatchHeuristicTest {

    @Test
    fun `no failures is never a mismatch`() {
        assertFalse(isVaultKeyMismatch(failures = 0, successes = 0))
        assertFalse(isVaultKeyMismatch(failures = 0, successes = 1))
        assertFalse(isVaultKeyMismatch(failures = 0, successes = 100))
    }

    @Test
    fun `single failure with at least one success is tolerated`() {
        // Rare per-entry corruption shouldn't brick the whole vault.
        assertFalse(isVaultKeyMismatch(failures = 1, successes = 1))
        assertFalse(isVaultKeyMismatch(failures = 1, successes = 9))
        assertFalse(isVaultKeyMismatch(failures = 1, successes = 99))
    }

    @Test
    fun `single failure with zero successes is a mismatch`() {
        // A one-entry vault whose single entry fails = definitely wrong key.
        assertTrue(isVaultKeyMismatch(failures = 1, successes = 0))
    }

    @Test
    fun `more than one failure is always a mismatch`() {
        assertTrue(isVaultKeyMismatch(failures = 2, successes = 8))
        assertTrue(isVaultKeyMismatch(failures = 5, successes = 50))
        assertTrue(isVaultKeyMismatch(failures = 10, successes = 0))
    }

    @Test
    fun `everything failed is a mismatch`() {
        assertTrue(isVaultKeyMismatch(failures = 3, successes = 0))
        assertTrue(isVaultKeyMismatch(failures = 100, successes = 0))
    }
}
