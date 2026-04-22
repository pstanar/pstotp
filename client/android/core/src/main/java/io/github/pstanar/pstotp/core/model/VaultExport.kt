package io.github.pstanar.pstotp.core.model

import java.util.Base64
import io.github.pstanar.pstotp.core.crypto.AesGcm
import io.github.pstanar.pstotp.core.crypto.Argon2
import io.github.pstanar.pstotp.core.crypto.Hkdf
import io.github.pstanar.pstotp.core.crypto.KeyDerivation
import org.json.JSONArray
import org.json.JSONObject
import java.security.SecureRandom

/**
 * Vault export/import in multiple formats.
 * Matches the web client's import-export.tsx.
 */
object VaultExport {

    private const val ENVELOPE_CONTEXT = "vault-password-envelope-v1"

    /**
     * Export entries as encrypted JSON.
     * Format: { version, format, salt, ciphertext, nonce }
     */
    fun exportEncrypted(entries: List<VaultEntry>, password: String): String {
        val plainJson = entriesToJsonArray(entries).toString().toByteArray(Charsets.UTF_8)

        val salt = KeyDerivation.generateSalt()
        val authKey = Argon2.hash(password, salt)
        val encKey = Hkdf.derive(authKey, ENVELOPE_CONTEXT)
        val encrypted = AesGcm.encrypt(encKey, plainJson)

        // Split nonce from ciphertext+tag
        val nonce = encrypted.copyOfRange(0, 12)
        val ciphertext = encrypted.copyOfRange(12, encrypted.size)

        return JSONObject().apply {
            put("version", 1)
            put("format", "pstotp-export")
            put("salt", Base64.getEncoder().encodeToString(salt))
            put("ciphertext", Base64.getEncoder().encodeToString(ciphertext))
            put("nonce", Base64.getEncoder().encodeToString(nonce))
        }.toString(2)
    }

    /**
     * Export entries as plain JSON (unencrypted).
     */
    fun exportPlain(entries: List<VaultEntry>): String {
        return JSONObject().apply {
            put("version", 1)
            put("format", "pstotp-plain")
            put("entries", entriesToJsonArray(entries))
        }.toString(2)
    }

    /**
     * Export entries as otpauth:// URIs, one per line.
     */
    fun exportOtpauthUris(entries: List<VaultEntry>): String {
        return entries.joinToString("\n") { entry ->
            OtpauthUri.build(VaultEntryPlaintext(
                issuer = entry.issuer,
                accountName = entry.accountName,
                secret = entry.secret,
                algorithm = entry.algorithm,
                digits = entry.digits,
                period = entry.period,
                icon = entry.icon,
            ))
        }
    }

    /**
     * Import from any supported format. Auto-detects between:
     *   - otpauth:// URIs (one per line)
     *   - otpauth-migration:// (Google Authenticator transfer)
     *   - pstotp-plain / pstotp-export (our own JSON)
     *   - Aegis plain JSON
     *   - 2FAS JSON
     *
     * @return list of parsed entries, or NeedsPassword for encrypted files.
     */
    fun importAutoDetect(content: String): ImportResult {
        val trimmed = content.trim()

        // otpauth-migration:// (Google Authenticator export) — check first
        // so it doesn't fall into the plain otpauth:// branch below.
        if (trimmed.startsWith("otpauth-migration://")) {
            return try {
                val entries = ExternalImports.tryParseGoogleAuthMigration(trimmed)
                    ?: return ImportResult.Error("Could not decode Google Authenticator export")
                if (entries.isEmpty()) ImportResult.Error("No TOTP accounts found in export")
                else ImportResult.Success(entries)
            } catch (e: Exception) {
                ImportResult.Error("Invalid Google Authenticator export: ${e.message}")
            }
        }

        // otpauth:// URI list
        if (trimmed.startsWith("otpauth://")) {
            val entries = trimmed.lines()
                .filter { it.trim().startsWith("otpauth://") }
                .map { OtpauthUri.parse(it.trim()) }
            return ImportResult.Success(entries)
        }

        // JSON formats — parse once, then dispatch by shape.
        val json = try {
            JSONObject(trimmed)
        } catch (_: Exception) {
            return ImportResult.Error("Unrecognized file format")
        }
        val format = json.optString("format", "")

        if (format == "pstotp-export" && json.has("ciphertext")) {
            return ImportResult.NeedsPassword
        }

        if (format == "pstotp-plain" && json.has("entries")) {
            val entries = jsonArrayToPlaintexts(json.getJSONArray("entries"))
            return ImportResult.Success(entries)
        }

        ExternalImports.tryParseAegis(json)?.let { return ImportResult.Success(it) }
        ExternalImports.tryParse2Fas(json)?.let { return ImportResult.Success(it) }

        return ImportResult.Error("Unrecognized file format")
    }

    /**
     * Import encrypted export file with password.
     */
    fun importEncrypted(content: String, password: String): List<VaultEntryPlaintext> {
        val json = JSONObject(content)
        val salt = Base64.getDecoder().decode(json.getString("salt"))
        val ciphertext = Base64.getDecoder().decode(json.getString("ciphertext"))
        val nonce = Base64.getDecoder().decode(json.getString("nonce"))

        val authKey = Argon2.hash(password, salt)
        val encKey = Hkdf.derive(authKey, ENVELOPE_CONTEXT)

        // Reconstruct payload: nonce || ciphertext+tag
        val payload = nonce + ciphertext
        val plainJson = AesGcm.decrypt(encKey, payload)

        val arr = JSONArray(String(plainJson, Charsets.UTF_8))
        return jsonArrayToPlaintexts(arr)
    }

    sealed class ImportResult {
        data class Success(val entries: List<VaultEntryPlaintext>) : ImportResult()
        data object NeedsPassword : ImportResult()
        data class Error(val message: String) : ImportResult()
    }

    private fun entriesToJsonArray(entries: List<VaultEntry>): JSONArray {
        val arr = JSONArray()
        for (e in entries) {
            arr.put(JSONObject().apply {
                put("issuer", e.issuer)
                put("accountName", e.accountName)
                put("secret", e.secret)
                put("algorithm", e.algorithm)
                put("digits", e.digits)
                put("period", e.period)
                if (e.icon != null) put("icon", e.icon)
            })
        }
        return arr
    }

    private fun jsonArrayToPlaintexts(arr: JSONArray): List<VaultEntryPlaintext> {
        return (0 until arr.length()).map { i ->
            val obj = arr.getJSONObject(i)
            VaultEntryPlaintext(
                issuer = obj.getString("issuer"),
                accountName = obj.getString("accountName"),
                secret = obj.getString("secret"),
                algorithm = obj.optString("algorithm", "SHA1"),
                digits = obj.optInt("digits", 6),
                period = obj.optInt("period", 30),
                icon = if (obj.has("icon")) obj.getString("icon") else null,
            )
        }
    }
}
