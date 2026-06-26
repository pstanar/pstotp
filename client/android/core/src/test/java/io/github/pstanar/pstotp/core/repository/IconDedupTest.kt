package io.github.pstanar.pstotp.core.repository

import io.github.pstanar.pstotp.core.model.LibraryIcon
import io.github.pstanar.pstotp.core.model.MAX_LIBRARY_ICONS
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class IconDedupTest {

    private var counter = 0
    private fun ids(): String = "id-${counter++}"
    private fun now(): String = "2026-01-01T00:00:00.000Z"

    private fun input(label: String, dataUrl: String, source: ByteArray? = null) =
        IconLibraryRepository.IconInput(label, dataUrl, source)

    @Test
    fun `findDuplicate matches by dataHash`() {
        val fp = IconDedup.fingerprint("data:image/png;base64,AAA", null)
        val existing = listOf(
            LibraryIcon("x", "L", "data:image/png;base64,AAA", now(), dataHash = fp.dataHash),
        )
        assertNotNull(IconDedup.findDuplicate(existing, fp))
    }

    @Test
    fun `findDuplicate matches by sourceHash even when data differs`() {
        val src = byteArrayOf(9, 8, 7)
        val stored = IconDedup.fingerprint("data:image/png;base64,ONE", src)
        val existing = listOf(
            LibraryIcon("x", "L", "data:image/png;base64,ONE", now(), dataHash = stored.dataHash, sourceHash = stored.sourceHash),
        )
        val incoming = IconDedup.fingerprint("data:image/png;base64,TWO", src)
        assertNotNull(IconDedup.findDuplicate(existing, incoming))
    }

    @Test
    fun `absent hashes never match`() {
        val legacy = listOf(LibraryIcon("x", "L", "data:image/png;base64,AAA", now()))
        val fp = IconDedup.fingerprint("data:image/png;base64,BBB", null)
        assertNull(IconDedup.findDuplicate(legacy, fp))
    }

    @Test
    fun `backfillHashes fills dataHash and leaves sourceHash null`() {
        val legacy = listOf(LibraryIcon("x", "L", "data:image/png;base64,LEG", now()))
        val filled = IconDedup.backfillHashes(legacy)
        assertNotNull(filled[0].dataHash)
        assertNull(filled[0].sourceHash)
    }

    @Test
    fun `planBatch dedups within batch and against existing`() {
        val existingFp = IconDedup.fingerprint("data:image/png;base64,EXIST", null)
        val existing = listOf(
            LibraryIcon("e", "existing", "data:image/png;base64,EXIST", now(), dataHash = existingFp.dataHash),
        )
        val (icons, result) = IconDedup.planBatch(
            existing,
            listOf(
                input("new1", "data:image/png;base64,N1"),
                input("dup-of-new1", "data:image/png;base64,N1"),
                input("dup-existing", "data:image/png;base64,EXIST"),
                input("new2", "data:image/png;base64,N2"),
            ),
            ::ids,
            ::now,
        )
        assertEquals(2, result.added)
        assertEquals(2, result.duplicates)
        assertEquals(0, result.overflow)
        assertEquals(3, icons.size)
    }

    @Test
    fun `planBatch counts items beyond the count cap as overflow`() {
        val items = (0 until MAX_LIBRARY_ICONS + 5).map {
            input("icon-$it", "data:image/png;base64,UNIQUE$it")
        }
        val (icons, result) = IconDedup.planBatch(emptyList(), items, ::ids, ::now)
        assertEquals(MAX_LIBRARY_ICONS, result.added)
        assertEquals(5, result.overflow)
        assertEquals(MAX_LIBRARY_ICONS, icons.size)
    }

    @Test
    fun `planAdd returns Duplicate for an identical data URL`() {
        val fp = IconDedup.fingerprint("data:image/png;base64,AAA", null)
        val existing = listOf(
            LibraryIcon("x", "L", "data:image/png;base64,AAA", now(), dataHash = fp.dataHash),
        )
        val plan = IconDedup.planAdd(existing, "again", "data:image/png;base64,AAA", null, ::ids, ::now)
        assertTrue(plan is IconDedup.AddPlan.Duplicate)
    }

    @Test
    fun `planAdd appends a fresh icon with both hashes`() {
        val plan = IconDedup.planAdd(emptyList(), "logo", "data:image/png;base64,AAA", byteArrayOf(1, 2, 3), ::ids, ::now)
        assertTrue(plan is IconDedup.AddPlan.Added)
        val icon = (plan as IconDedup.AddPlan.Added).icons.single()
        assertNotNull(icon.dataHash)
        assertNotNull(icon.sourceHash)
    }
}
