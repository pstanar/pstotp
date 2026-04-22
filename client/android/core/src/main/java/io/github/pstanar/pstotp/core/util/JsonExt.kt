package io.github.pstanar.pstotp.core.util

import org.json.JSONObject

/**
 * Return the string value at [key], or null if the key is absent,
 * explicitly JSON-null, or empty. Treating empty strings as null
 * matches how server DTOs encode optional tokens / GUIDs.
 */
internal fun JSONObject.optStringOrNull(key: String): String? =
    if (!has(key) || isNull(key)) null else optString(key).takeIf { it.isNotEmpty() }
