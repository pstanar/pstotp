package io.github.pstanar.pstotp.core.model

import io.github.pstanar.pstotp.core.crypto.Base32
import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder
import java.util.Base64

/**
 * Parsers for third-party TOTP export formats, to make migration from
 * common authenticators frictionless:
 *   - Google Authenticator (otpauth-migration:// URIs, protobuf payload)
 *   - Aegis (plain / unencrypted JSON only — encrypted Aegis vaults use
 *     scrypt + password slots that we don't want to reimplement)
 *   - 2FAS (plain JSON export)
 *
 * Each `tryParseX` returns null when the content doesn't look like the
 * given format, so auto-detect can just probe them in turn without
 * throwing.
 */
internal object ExternalImports {

    // --- Google Authenticator ---------------------------------------------

    /**
     * Parses an otpauth-migration:// URI (the "Transfer accounts" QR code
     * Google Authenticator emits). One URI typically contains multiple
     * accounts packed into a base64 protobuf payload.
     */
    fun tryParseGoogleAuthMigration(content: String): List<VaultEntryPlaintext>? {
        val line = content.trim()
        if (!line.startsWith("otpauth-migration://")) return null

        val query = URI(line).rawQuery ?: return null
        val dataParam = query.split('&')
            .firstOrNull { it.startsWith("data=") }
            ?.removePrefix("data=")
            ?: return null

        // The Google export encodes data with standard base64 but often
        // URL-encodes the padding characters.
        val b64 = URLDecoder.decode(dataParam, Charsets.UTF_8)
        val payload = Base64.getDecoder().decode(b64)
        return parseMigrationPayload(payload)
    }

    private fun parseMigrationPayload(bytes: ByteArray): List<VaultEntryPlaintext> {
        val r = ProtoReader(bytes)
        val out = mutableListOf<VaultEntryPlaintext>()
        while (!r.eof()) {
            val (field, wire) = r.readTag()
            if (field == 1 && wire == WireType.LEN) {
                val inner = r.readLengthDelimited()
                parseOtpParameters(inner)?.let(out::add)
            } else {
                r.skipField(wire)
            }
        }
        return out
    }

    private fun parseOtpParameters(bytes: ByteArray): VaultEntryPlaintext? {
        val r = ProtoReader(bytes)
        var secret = ByteArray(0)
        var name = ""
        var issuer = ""
        var algo = 1
        var digits = 1
        var type = 2
        while (!r.eof()) {
            val (field, wire) = r.readTag()
            when (field) {
                1 -> secret = r.readLengthDelimited()
                2 -> name = String(r.readLengthDelimited(), Charsets.UTF_8)
                3 -> issuer = String(r.readLengthDelimited(), Charsets.UTF_8)
                4 -> algo = r.readVarint().toInt()
                5 -> digits = r.readVarint().toInt()
                6 -> type = r.readVarint().toInt()
                else -> r.skipField(wire)
            }
        }
        if (type != 2) return null // HOTP — we only import TOTP
        val algorithmName = when (algo) {
            2 -> "SHA256"
            3 -> "SHA512"
            else -> "SHA1"
        }
        val digitCount = if (digits == 2) 8 else 6
        val (resolvedIssuer, resolvedAccount) = resolveIssuerAndAccount(issuer, name)
        return VaultEntryPlaintext(
            issuer = resolvedIssuer.ifBlank { "Unknown" },
            accountName = resolvedAccount.ifBlank { resolvedIssuer.ifBlank { "Account" } },
            secret = Base32.encode(secret),
            algorithm = algorithmName,
            digits = digitCount,
            period = 30,
            icon = null,
        )
    }

    /**
     * Google Authenticator is inconsistent about what it puts in the `name`
     * field when `issuer` is also populated: sometimes just the account,
     * sometimes "Issuer:account" duplicated. Rule here:
     *   - no colon in name                 → use name as-is
     *   - issuer blank + colon in name     → split "Issuer:account"
     *   - issuer matches prefix before ':' → strip the redundant prefix
     *   - otherwise                        → the colon is part of the
     *                                        account itself, leave name alone
     */
    private fun resolveIssuerAndAccount(issuer: String, name: String): Pair<String, String> {
        val colonIndex = name.indexOf(':')
        if (colonIndex < 0) return issuer to name
        val before = name.substring(0, colonIndex).trim()
        val after = name.substring(colonIndex + 1).trim()
        return when {
            issuer.isBlank() -> before to after
            before.equals(issuer, ignoreCase = true) -> issuer to after
            else -> issuer to name
        }
    }

    // --- Aegis -----------------------------------------------------------

    /**
     * Plain (unencrypted) Aegis export:
     *   { "version":1, "header":{"slots":null,...}, "db":{"entries":[...]}}
     * Returns null if the shape doesn't match.
     */
    fun tryParseAegis(json: JSONObject): List<VaultEntryPlaintext>? {
        val db = json.optJSONObject("db") ?: return null
        val entries = db.optJSONArray("entries") ?: return null
        // Only claim the format if the top-level "header" is present too —
        // otherwise a different exporter happens to have db.entries.
        if (!json.has("header")) return null
        val out = mutableListOf<VaultEntryPlaintext>()
        for (i in 0 until entries.length()) {
            val e = entries.optJSONObject(i) ?: continue
            if (e.optString("type") != "totp") continue
            val info = e.optJSONObject("info") ?: continue
            val secret = info.optString("secret").takeIf { it.isNotBlank() } ?: continue
            out.add(
                VaultEntryPlaintext(
                    issuer = e.optString("issuer").ifBlank { "Unknown" },
                    accountName = e.optString("name").ifBlank { "Account" },
                    secret = secret.uppercase(),
                    algorithm = info.optString("algo", "SHA1").uppercase(),
                    digits = info.optInt("digits", 6),
                    period = info.optInt("period", 30),
                    icon = null,
                ),
            )
        }
        return out.takeIf { it.isNotEmpty() }
    }

    // --- 2FAS ------------------------------------------------------------

    fun tryParse2Fas(json: JSONObject): List<VaultEntryPlaintext>? {
        val services = json.optJSONArray("services") ?: return null
        // `schemaVersion` is the 2FAS-specific anchor — avoids claiming any
        // JSON that happens to have a `services` array.
        if (!json.has("schemaVersion")) return null
        val out = mutableListOf<VaultEntryPlaintext>()
        for (i in 0 until services.length()) {
            val svc = services.optJSONObject(i) ?: continue
            val secret = svc.optString("secret").takeIf { it.isNotBlank() } ?: continue
            val otp = svc.optJSONObject("otp") ?: JSONObject()
            val issuer = otp.optString("issuer").ifBlank { svc.optString("name") }.ifBlank { "Unknown" }
            val account = otp.optString("account").ifBlank { svc.optString("name") }.ifBlank { issuer }
            out.add(
                VaultEntryPlaintext(
                    issuer = issuer,
                    accountName = account,
                    secret = secret.uppercase(),
                    algorithm = otp.optString("algorithm", "SHA1").uppercase(),
                    digits = otp.optInt("digits", 6),
                    period = otp.optInt("period", 30),
                    icon = null,
                ),
            )
        }
        return out.takeIf { it.isNotEmpty() }
    }

    // --- Minimal protobuf reader -----------------------------------------

    private object WireType {
        const val VARINT = 0
        const val LEN = 2
    }

    private class ProtoReader(private val buf: ByteArray) {
        private var pos: Int = 0
        fun eof() = pos >= buf.size

        fun readTag(): Pair<Int, Int> {
            val tag = readVarint().toInt()
            return (tag ushr 3) to (tag and 0x7)
        }

        fun readVarint(): Long {
            var result = 0L
            var shift = 0
            while (true) {
                if (pos >= buf.size) throw IllegalArgumentException("truncated varint")
                val b = buf[pos++].toInt() and 0xff
                result = result or ((b.toLong() and 0x7fL) shl shift)
                if (b and 0x80 == 0) return result
                shift += 7
                if (shift > 63) throw IllegalArgumentException("varint too long")
            }
        }

        fun readLengthDelimited(): ByteArray {
            val len = readVarint().toInt()
            if (len < 0 || pos + len > buf.size) throw IllegalArgumentException("bad length-delimited")
            val out = buf.copyOfRange(pos, pos + len)
            pos += len
            return out
        }

        fun skipField(wire: Int) {
            when (wire) {
                WireType.VARINT -> readVarint()
                1 -> skipBytes(8)        // fixed64
                WireType.LEN -> readLengthDelimited()
                5 -> skipBytes(4)        // fixed32
                else -> throw IllegalArgumentException("unsupported wire type $wire")
            }
        }

        private fun skipBytes(n: Int) {
            if (pos + n > buf.size) throw IllegalArgumentException("truncated fixed-width field")
            pos += n
        }
    }
}
