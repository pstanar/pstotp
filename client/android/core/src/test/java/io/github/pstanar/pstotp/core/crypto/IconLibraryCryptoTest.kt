package io.github.pstanar.pstotp.core.crypto

import io.github.pstanar.pstotp.core.model.IconLibraryBlob
import io.github.pstanar.pstotp.core.model.LibraryIcon
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.security.SecureRandom

class IconLibraryCryptoTest {

    private fun randomKey(): ByteArray = ByteArray(32).also { SecureRandom().nextBytes(it) }

    private val sample = IconLibraryBlob(
        version = 1,
        icons = listOf(
            LibraryIcon(
                id = "11111111-1111-1111-1111-111111111111",
                label = "Company logo",
                data = "data:image/png;base64,iVBORw0KGgo=",
                createdAt = "2026-04-22T00:00:00.000Z",
            ),
            LibraryIcon(
                id = "22222222-2222-2222-2222-222222222222",
                label = "Another",
                data = "data:image/png;base64,XYZ=",
                createdAt = "2026-04-22T01:00:00.000Z",
            ),
        ),
    )

    @Test
    fun `roundtrip preserves icons and version`() {
        val key = randomKey()
        val encrypted = IconLibraryCrypto.encrypt(key, sample)
        val decrypted = IconLibraryCrypto.decrypt(key, encrypted)

        assertEquals(sample.version, decrypted.version)
        assertEquals(sample.icons.size, decrypted.icons.size)
        assertEquals(sample.icons[0], decrypted.icons[0])
        assertEquals(sample.icons[1], decrypted.icons[1])
    }

    @Test
    fun `fresh nonce every call — same input yields different ciphertext`() {
        val key = randomKey()
        val a = IconLibraryCrypto.encrypt(key, sample)
        val b = IconLibraryCrypto.encrypt(key, sample)
        assertNotEquals("Two encryptions of the same blob should differ (fresh nonce)",
            a.toList(), b.toList())
    }

    @Test
    fun `decrypt with wrong key fails the MAC`() {
        val encrypted = IconLibraryCrypto.encrypt(randomKey(), sample)
        // Any javax.crypto failure is fine; Assert.assertThrows covers them all.
        assertThrows(Exception::class.java) {
            IconLibraryCrypto.decrypt(randomKey(), encrypted)
        }
    }

    @Test
    fun `empty library roundtrips cleanly`() {
        val key = randomKey()
        val empty = IconLibraryBlob(version = 1, icons = emptyList())
        val decrypted = IconLibraryCrypto.decrypt(key, IconLibraryCrypto.encrypt(key, empty))
        assertEquals(0, decrypted.icons.size)
    }
}
