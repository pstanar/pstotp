package io.github.pstanar.pstotp.core.model

import android.net.Uri

/**
 * Parse and build otpauth:// URIs (RFC for TOTP provisioning).
 * Format: otpauth://totp/[Issuer:]Account?secret=X&issuer=X&algorithm=SHA1&digits=6&period=30
 */
object OtpauthUri {

    /**
     * Parse an otpauth:// URI into a VaultEntryPlaintext.
     * @throws IllegalArgumentException if the URI is invalid
     */
    fun parse(uriString: String): VaultEntryPlaintext {
        val uri = Uri.parse(uriString)
        require(uri.scheme == "otpauth") { "Not an otpauth URI" }
        require(uri.host == "totp") { "Only TOTP is supported (not HOTP)" }

        val path = uri.path?.removePrefix("/") ?: ""
        val secret = uri.getQueryParameter("secret")
            ?: throw IllegalArgumentException("Missing secret parameter")

        // Parse label: "Issuer:Account" or just "Account"
        val (pathIssuer, accountName) = if (":" in path) {
            val parts = path.split(":", limit = 2)
            Uri.decode(parts[0]) to Uri.decode(parts[1])
        } else {
            null to Uri.decode(path)
        }

        // Query param issuer takes precedence over path issuer
        val issuer = uri.getQueryParameter("issuer") ?: pathIssuer ?: ""

        val algorithm = uri.getQueryParameter("algorithm")?.uppercase() ?: "SHA1"
        require(algorithm in listOf("SHA1", "SHA256", "SHA512")) { "Unsupported algorithm: $algorithm" }

        val digits = uri.getQueryParameter("digits")?.toIntOrNull() ?: 6
        require(digits in 4..10) { "Digits must be between 4 and 10" }

        val period = uri.getQueryParameter("period")?.toIntOrNull() ?: 30
        require(period > 0) { "Period must be positive" }

        return VaultEntryPlaintext(
            issuer = issuer,
            accountName = accountName,
            secret = secret.uppercase().replace(" ", ""),
            algorithm = algorithm,
            digits = digits,
            period = period,
        )
    }

    /**
     * Build an otpauth:// URI from a vault entry.
     */
    fun build(entry: VaultEntryPlaintext): String {
        val label = Uri.encode(entry.accountName)

        // Build manually to avoid double-encoding from appendPath
        val params = mutableListOf("secret=${Uri.encode(entry.secret)}")
        if (entry.issuer.isNotEmpty()) params.add("issuer=${Uri.encode(entry.issuer)}")
        params.add("algorithm=${entry.algorithm}")
        params.add("digits=${entry.digits}")
        params.add("period=${entry.period}")

        return "otpauth://totp/$label?${params.joinToString("&")}"
    }
}
