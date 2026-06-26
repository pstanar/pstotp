package io.github.pstanar.pstotp.core.repository

import io.github.pstanar.pstotp.core.model.LibraryIcon

/**
 * Decides whether a connected icon-library mutation may proceed on the current
 * in-memory base, or must first hydrate from the server. Pure orchestration —
 * the actual push/pull is injected as [pull] — so the fail-closed contract is
 * unit-testable without the Android ViewModel:
 *   - standalone (not connected): the local cache is authoritative — proceed
 *   - already hydrated this session: proceed
 *   - otherwise: pull once; on success the pulled icons become the new base; on
 *     failure fail closed so the caller refuses to mutate (a stale/empty local
 *     base must never overwrite the server's real library).
 */
object IconLibrarySync {

    class Outcome(
        /** True if the caller may safely mutate the library. */
        val authoritative: Boolean,
        /** New base icons to adopt (from a successful pull), or null to keep the current list. */
        val icons: List<LibraryIcon>?,
        /** The session "hydrated" flag the caller should store. */
        val hydrated: Boolean,
    )

    suspend fun hydrateIfNeeded(
        connected: Boolean,
        hydrated: Boolean,
        pull: suspend () -> List<LibraryIcon>,
    ): Outcome = when {
        !connected -> Outcome(authoritative = true, icons = null, hydrated = hydrated)
        hydrated -> Outcome(authoritative = true, icons = null, hydrated = true)
        else -> try {
            Outcome(authoritative = true, icons = pull(), hydrated = true)
        } catch (_: Exception) {
            Outcome(authoritative = false, icons = null, hydrated = false)
        }
    }
}
