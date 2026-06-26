package io.github.pstanar.pstotp.core.repository

import io.github.pstanar.pstotp.core.model.LibraryIcon
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class IconLibrarySyncTest {

    private fun icon(id: String) =
        LibraryIcon(id, "L", "data:image/png;base64,$id", "2026-01-01T00:00:00Z")

    @Test
    fun `standalone is authoritative without pulling`() = runBlocking {
        var pulled = false
        val o = IconLibrarySync.hydrateIfNeeded(connected = false, hydrated = false) {
            pulled = true
            emptyList()
        }
        assertTrue(o.authoritative)
        assertNull(o.icons)
        assertFalse(o.hydrated)
        assertFalse("standalone must not pull", pulled)
    }

    @Test
    fun `already hydrated is authoritative without pulling`() = runBlocking {
        var pulled = false
        val o = IconLibrarySync.hydrateIfNeeded(connected = true, hydrated = true) {
            pulled = true
            emptyList()
        }
        assertTrue(o.authoritative)
        assertTrue(o.hydrated)
        assertFalse("already hydrated must not pull", pulled)
    }

    @Test
    fun `connected and unhydrated pulls and adopts the server icons`() = runBlocking {
        val server = listOf(icon("a"), icon("b"))
        val o = IconLibrarySync.hydrateIfNeeded(connected = true, hydrated = false) { server }
        assertTrue(o.authoritative)
        assertEquals(server, o.icons)
        assertTrue(o.hydrated)
    }

    @Test
    fun `pull failure fails closed`() = runBlocking {
        val o = IconLibrarySync.hydrateIfNeeded(connected = true, hydrated = false) {
            throw RuntimeException("network down")
        }
        assertFalse("must not be authoritative when the pull failed", o.authoritative)
        assertNull(o.icons)
        assertFalse(o.hydrated)
    }
}
