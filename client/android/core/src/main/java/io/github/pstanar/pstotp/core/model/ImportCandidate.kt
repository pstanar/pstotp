package io.github.pstanar.pstotp.core.model

/**
 * Action to take for a duplicate entry during import.
 */
enum class ImportAction {
    /** Overwrite the existing entry with imported data. */
    OVERWRITE,
    /** Add as a new entry with a deduplicated name. */
    ADD_COPY,
    /** Skip this entry entirely. */
    SKIP,
}

/**
 * An imported entry paired with its conflict resolution state.
 * Built by comparing parsed entries against the existing vault.
 */
data class ImportCandidate(
    val imported: VaultEntryPlaintext,
    val existingMatch: VaultEntry?,
    val action: ImportAction,
) {
    val isDuplicate: Boolean get() = existingMatch != null

    companion object {
        /**
         * Build candidates by matching imported entries against existing vault entries.
         * Matches on issuer + accountName (case-insensitive).
         */
        fun buildCandidates(
            imported: List<VaultEntryPlaintext>,
            existing: List<VaultEntry>,
        ): List<ImportCandidate> {
            return imported.map { entry ->
                val match = existing.find { e ->
                    e.issuer.equals(entry.issuer, ignoreCase = true) &&
                        e.accountName.equals(entry.accountName, ignoreCase = true)
                }
                ImportCandidate(
                    imported = entry,
                    existingMatch = match,
                    action = if (match != null) ImportAction.OVERWRITE else ImportAction.ADD_COPY,
                )
            }
        }

        /**
         * Generate a unique account name by appending (2), (3), etc.
         */
        fun makeUniqueName(name: String, issuer: String, existing: List<VaultEntry>): String {
            val taken = existing
                .filter { it.issuer.equals(issuer, ignoreCase = true) }
                .map { it.accountName.lowercase() }
                .toSet()
            if (name.lowercase() !in taken) return name
            var i = 2
            while (true) {
                val candidate = "$name ($i)"
                if (candidate.lowercase() !in taken) return candidate
                i++
            }
        }
    }
}
