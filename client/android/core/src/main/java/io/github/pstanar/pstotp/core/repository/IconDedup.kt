package io.github.pstanar.pstotp.core.repository

import io.github.pstanar.pstotp.core.crypto.Hash
import io.github.pstanar.pstotp.core.model.IconLibraryBlob
import io.github.pstanar.pstotp.core.model.LibraryIcon
import io.github.pstanar.pstotp.core.model.MAX_LIBRARY_BYTES
import io.github.pstanar.pstotp.core.model.MAX_LIBRARY_ICONS

/**
 * Pure content-de-duplication logic for the icon library, independent of
 * storage/network so it can be unit-tested directly. Mirrors the web
 * client's store helpers. `dataHash` hashes the resized data-URL string
 * (UTF-8); `sourceHash` hashes the raw pre-resize bytes. Dedup matches if
 * EITHER hash matches; absent hashes never match (missing != equal).
 */
internal object IconDedup {

    /**
     * Bytes AES-GCM packing adds on top of the plaintext: nonce(12) + tag(16).
     * The server caps the *encrypted* payload, so the plaintext JSON budget
     * must reserve this or a near-limit write passes here and 400s server-side.
     */
    private const val AEAD_OVERHEAD = 28
    private const val MAX_PLAINTEXT_BYTES = MAX_LIBRARY_BYTES - AEAD_OVERHEAD

    class Fingerprint(val dataHash: String, val sourceHash: String?)

    fun fingerprint(dataUrl: String, sourceBytes: ByteArray?) = Fingerprint(
        dataHash = Hash.sha256Hex(dataUrl.toByteArray(Charsets.UTF_8)),
        sourceHash = sourceBytes?.let { Hash.sha256Hex(it) },
    )

    fun findDuplicate(icons: List<LibraryIcon>, fp: Fingerprint): LibraryIcon? =
        icons.firstOrNull { i ->
            (i.dataHash != null && i.dataHash == fp.dataHash) ||
                (i.sourceHash != null && fp.sourceHash != null && i.sourceHash == fp.sourceHash)
        }

    /** Compute dataHash for any icon missing it (legacy blobs). */
    fun backfillHashes(icons: List<LibraryIcon>): List<LibraryIcon> =
        icons.map {
            if (it.dataHash != null) it
            else it.copy(dataHash = Hash.sha256Hex(it.data.toByteArray(Charsets.UTF_8)))
        }

    /** Approx encrypted-payload size: the plaintext JSON byte length. */
    fun blobByteLength(icons: List<LibraryIcon>): Int =
        IconLibraryBlob(version = 1, icons = icons).toJsonString().toByteArray(Charsets.UTF_8).size

    private fun makeIcon(
        label: String,
        dataUrl: String,
        fp: Fingerprint,
        id: String,
        createdAt: String,
    ) = LibraryIcon(
        id = id,
        label = label.ifBlank { "Icon" },
        data = dataUrl,
        createdAt = createdAt,
        dataHash = fp.dataHash,
        sourceHash = fp.sourceHash,
    )

    sealed interface AddPlan {
        /** An existing icon already matches — caller keeps the current list. */
        object Duplicate : AddPlan
        object CountCapExceeded : AddPlan
        object ByteCapExceeded : AddPlan
        class Added(val icons: List<LibraryIcon>) : AddPlan
    }

    fun planAdd(
        current: List<LibraryIcon>,
        label: String,
        dataUrl: String,
        sourceBytes: ByteArray?,
        idFactory: () -> String,
        nowFactory: () -> String,
    ): AddPlan {
        val fp = fingerprint(dataUrl, sourceBytes)
        if (findDuplicate(current, fp) != null) return AddPlan.Duplicate
        if (current.size >= MAX_LIBRARY_ICONS) return AddPlan.CountCapExceeded
        val next = current + makeIcon(label, dataUrl, fp, idFactory(), nowFactory())
        if (blobByteLength(next) > MAX_PLAINTEXT_BYTES) return AddPlan.ByteCapExceeded
        return AddPlan.Added(next)
    }

    /**
     * Plan a batch add without persisting. De-dups against [current] and
     * within the batch; respects both caps, counting skipped icons as
     * overflow. Returns the resulting list and a tally.
     */
    fun planBatch(
        current: List<LibraryIcon>,
        items: List<IconLibraryRepository.IconInput>,
        idFactory: () -> String,
        nowFactory: () -> String,
    ): Pair<List<LibraryIcon>, IconLibraryRepository.BatchResult> {
        val next = current.toMutableList()
        var added = 0
        var duplicates = 0
        var overflow = 0
        // Track the JSON byte total incrementally — adding one icon costs its
        // own serialised length plus a separator — so we don't re-serialise the
        // whole growing list on every item.
        var bytes = blobByteLength(next)
        for (item in items) {
            val fp = fingerprint(item.dataUrl, item.sourceBytes)
            when {
                findDuplicate(next, fp) != null -> duplicates++
                next.size >= MAX_LIBRARY_ICONS -> overflow++
                else -> {
                    val candidate = makeIcon(item.label, item.dataUrl, fp, idFactory(), nowFactory())
                    val cost = candidate.toJson().toString().toByteArray(Charsets.UTF_8).size + 1
                    if (bytes + cost > MAX_PLAINTEXT_BYTES) {
                        overflow++
                    } else {
                        next.add(candidate)
                        bytes += cost
                        added++
                    }
                }
            }
        }
        return next.toList() to IconLibraryRepository.BatchResult(added, duplicates, overflow)
    }
}
