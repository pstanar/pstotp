package io.github.pstanar.pstotp.core

/**
 * Brand colors for common TOTP services.
 * Matches the web client's service-icons.ts.
 */
data class ServiceBrand(val bg: Long, val fg: Long, val letter: String? = null)

object ServiceBrands {
    private val brands = mapOf(
        "google" to ServiceBrand(0xFF4285F4, 0xFFFFFFFF),
        "github" to ServiceBrand(0xFF24292E, 0xFFFFFFFF),
        "gitlab" to ServiceBrand(0xFFFC6D26, 0xFFFFFFFF),
        "microsoft" to ServiceBrand(0xFF00A4EF, 0xFFFFFFFF),
        "amazon" to ServiceBrand(0xFFFF9900, 0xFF111111),
        "aws" to ServiceBrand(0xFF232F3E, 0xFFFF9900, "A"),
        "apple" to ServiceBrand(0xFF000000, 0xFFFFFFFF),
        "facebook" to ServiceBrand(0xFF1877F2, 0xFFFFFFFF),
        "meta" to ServiceBrand(0xFF1877F2, 0xFFFFFFFF),
        "twitter" to ServiceBrand(0xFF1DA1F2, 0xFFFFFFFF),
        "x" to ServiceBrand(0xFF000000, 0xFFFFFFFF),
        "discord" to ServiceBrand(0xFF5865F2, 0xFFFFFFFF),
        "slack" to ServiceBrand(0xFF4A154B, 0xFFFFFFFF),
        "dropbox" to ServiceBrand(0xFF0061FF, 0xFFFFFFFF),
        "reddit" to ServiceBrand(0xFFFF4500, 0xFFFFFFFF),
        "twitch" to ServiceBrand(0xFF9146FF, 0xFFFFFFFF),
        "steam" to ServiceBrand(0xFF1B2838, 0xFFFFFFFF),
        "digitalocean" to ServiceBrand(0xFF0080FF, 0xFFFFFFFF, "D"),
        "cloudflare" to ServiceBrand(0xFFF38020, 0xFFFFFFFF),
        "stripe" to ServiceBrand(0xFF635BFF, 0xFFFFFFFF),
        "paypal" to ServiceBrand(0xFF003087, 0xFFFFFFFF),
        "coinbase" to ServiceBrand(0xFF0052FF, 0xFFFFFFFF),
        "binance" to ServiceBrand(0xFFF0B90B, 0xFF111111),
        "bitwarden" to ServiceBrand(0xFF175DDC, 0xFFFFFFFF),
        "1password" to ServiceBrand(0xFF1A8CFF, 0xFFFFFFFF, "1"),
        "lastpass" to ServiceBrand(0xFFD32D27, 0xFFFFFFFF),
        "docker" to ServiceBrand(0xFF2496ED, 0xFFFFFFFF),
        "linkedin" to ServiceBrand(0xFF0A66C2, 0xFFFFFFFF),
        "instagram" to ServiceBrand(0xFFE4405F, 0xFFFFFFFF),
        "spotify" to ServiceBrand(0xFF1DB954, 0xFFFFFFFF),
        "netflix" to ServiceBrand(0xFFE50914, 0xFFFFFFFF),
        "proton" to ServiceBrand(0xFF6D4AFF, 0xFFFFFFFF),
        "zoom" to ServiceBrand(0xFF2D8CFF, 0xFFFFFFFF),
        "figma" to ServiceBrand(0xFFF24E1E, 0xFFFFFFFF),
        "notion" to ServiceBrand(0xFF000000, 0xFFFFFFFF),
        "vercel" to ServiceBrand(0xFF000000, 0xFFFFFFFF),
        "shopify" to ServiceBrand(0xFF96BF48, 0xFFFFFFFF),
        "wordpress" to ServiceBrand(0xFF21759B, 0xFFFFFFFF),
        "okta" to ServiceBrand(0xFF007DC1, 0xFFFFFFFF),
        "epic" to ServiceBrand(0xFF2F2D2E, 0xFFFFFFFF),
        "nintendo" to ServiceBrand(0xFFE60012, 0xFFFFFFFF),
        "playstation" to ServiceBrand(0xFF003791, 0xFFFFFFFF),
        "xbox" to ServiceBrand(0xFF107C10, 0xFFFFFFFF),
    )

    fun get(issuer: String): ServiceBrand? {
        // Guard the empty / non-alphanumeric cases up front:
        //   - `issuer.first()` (line below) throws on empty.
        //   - `name.contains(key)` is true for every brand when `key` is
        //     empty (every string contains ""), so without this guard
        //     the first brand always "matches" and we'd return arbitrary
        //     colors for blank issuers.
        if (issuer.isBlank()) return null
        val key = issuer.lowercase().replace(Regex("[^a-z0-9]"), "")
        if (key.isEmpty()) return null
        for ((name, brand) in brands) {
            if (key.contains(name) || name.contains(key)) {
                return brand.copy(letter = brand.letter ?: issuer.first().uppercase())
            }
        }
        return null
    }
}
