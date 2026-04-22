package io.github.pstanar.pstotp.core.model

enum class SortMode(val storageKey: String, val label: String) {
    MANUAL("manual", "Manual"),
    ALPHABETICAL("alphabetical", "Alphabetical"),
    LRU("lru", "Recently used"),
    MFU("mfu", "Most used"),
    ;

    companion object {
        fun fromStorageKey(key: String?): SortMode =
            entries.firstOrNull { it.storageKey == key } ?: MANUAL
    }
}
