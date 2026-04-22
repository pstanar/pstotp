package io.github.pstanar.pstotp.core.model

/**
 * Preset durations for auto-lock after backgrounding. NEVER uses
 * Long.MAX_VALUE so the `duration > timeout` check in MainActivity never
 * fires; no special-case needed elsewhere.
 */
enum class LockTimeout(val millis: Long, val label: String) {
    ONE_MIN(60_000L, "1 minute"),
    FIVE_MIN(5 * 60_000L, "5 minutes"),
    FIFTEEN_MIN(15 * 60_000L, "15 minutes"),
    ONE_HOUR(60 * 60_000L, "1 hour"),
    NEVER(Long.MAX_VALUE, "Never"),
    ;

    companion object {
        /** Nearest preset to a persisted value; falls back to the default. */
        fun fromMillis(ms: Long?, default: LockTimeout = FIVE_MIN): LockTimeout {
            if (ms == null) return default
            return entries.firstOrNull { it.millis == ms } ?: default
        }
    }
}
