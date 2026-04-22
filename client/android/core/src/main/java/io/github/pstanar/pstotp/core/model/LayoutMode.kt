package io.github.pstanar.pstotp.core.model

enum class LayoutMode(val storageKey: String, val label: String) {
    LIST("list", "List"),
    GRID("grid", "Grid"),
    ;

    companion object {
        fun fromStorageKey(key: String?): LayoutMode =
            entries.firstOrNull { it.storageKey == key } ?: LIST
    }
}
