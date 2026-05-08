package io.github.pstanar.pstotp.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ServiceBrandsTest {

    /**
     * Empty issuer used to crash with `NoSuchElementException` because
     * `name.contains(key)` is true for every brand when `key` is the
     * empty string (every string contains ""), so the loop "matched"
     * the first brand and then called `issuer.first()` on the empty
     * source. Guarded now — empty/blank/non-alphanumeric returns null.
     */
    @Test
    fun `empty issuer returns null instead of crashing`() {
        assertNull(ServiceBrands.get(""))
    }

    @Test
    fun `whitespace-only issuer returns null`() {
        assertNull(ServiceBrands.get("   "))
    }

    @Test
    fun `non-alphanumeric issuer returns null`() {
        // Sanitised key is empty after stripping non-[a-z0-9].
        assertNull(ServiceBrands.get("🔒"))
    }

    @Test
    fun `known brand still resolves with first-letter fallback`() {
        // GitHub doesn't carry a preset letter in the brand table, so
        // the fallback path that takes `issuer.first()` is exercised.
        val brand = ServiceBrands.get("GitHub")
        assertEquals("G", brand?.letter)
    }
}
