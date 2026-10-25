import Foundation

/// Brand colors for common TOTP services. Matches the Android `ServiceBrands` and the web
/// client's service-icons.ts. Colors are 0xAARRGGBB.
public struct ServiceBrand: Equatable, Sendable {
    public let bg: UInt32
    public let fg: UInt32
    public let letter: String?

    public init(bg: UInt32, fg: UInt32, letter: String? = nil) {
        self.bg = bg
        self.fg = fg
        self.letter = letter
    }
}

public enum ServiceBrands {
    private static let white: UInt32 = 0xFFFFFFFF

    /// Ordered: the first brand whose name matches wins, as on Android.
    private static let brands: [(name: String, brand: ServiceBrand)] = [
        ("google", ServiceBrand(bg: 0xFF4285F4, fg: white)),
        ("github", ServiceBrand(bg: 0xFF24292E, fg: white)),
        ("gitlab", ServiceBrand(bg: 0xFFFC6D26, fg: white)),
        ("microsoft", ServiceBrand(bg: 0xFF00A4EF, fg: white)),
        ("amazon", ServiceBrand(bg: 0xFFFF9900, fg: 0xFF111111)),
        ("aws", ServiceBrand(bg: 0xFF232F3E, fg: 0xFFFF9900, letter: "A")),
        ("apple", ServiceBrand(bg: 0xFF000000, fg: white)),
        ("facebook", ServiceBrand(bg: 0xFF1877F2, fg: white)),
        ("meta", ServiceBrand(bg: 0xFF1877F2, fg: white)),
        ("twitter", ServiceBrand(bg: 0xFF1DA1F2, fg: white)),
        ("x", ServiceBrand(bg: 0xFF000000, fg: white)),
        ("discord", ServiceBrand(bg: 0xFF5865F2, fg: white)),
        ("slack", ServiceBrand(bg: 0xFF4A154B, fg: white)),
        ("dropbox", ServiceBrand(bg: 0xFF0061FF, fg: white)),
        ("reddit", ServiceBrand(bg: 0xFFFF4500, fg: white)),
        ("twitch", ServiceBrand(bg: 0xFF9146FF, fg: white)),
        ("steam", ServiceBrand(bg: 0xFF1B2838, fg: white)),
        ("digitalocean", ServiceBrand(bg: 0xFF0080FF, fg: white, letter: "D")),
        ("cloudflare", ServiceBrand(bg: 0xFFF38020, fg: white)),
        ("stripe", ServiceBrand(bg: 0xFF635BFF, fg: white)),
        ("paypal", ServiceBrand(bg: 0xFF003087, fg: white)),
        ("coinbase", ServiceBrand(bg: 0xFF0052FF, fg: white)),
        ("binance", ServiceBrand(bg: 0xFFF0B90B, fg: 0xFF111111)),
        ("bitwarden", ServiceBrand(bg: 0xFF175DDC, fg: white)),
        ("1password", ServiceBrand(bg: 0xFF1A8CFF, fg: white, letter: "1")),
        ("lastpass", ServiceBrand(bg: 0xFFD32D27, fg: white)),
        ("docker", ServiceBrand(bg: 0xFF2496ED, fg: white)),
        ("linkedin", ServiceBrand(bg: 0xFF0A66C2, fg: white)),
        ("instagram", ServiceBrand(bg: 0xFFE4405F, fg: white)),
        ("spotify", ServiceBrand(bg: 0xFF1DB954, fg: white)),
        ("netflix", ServiceBrand(bg: 0xFFE50914, fg: white)),
        ("proton", ServiceBrand(bg: 0xFF6D4AFF, fg: white)),
        ("zoom", ServiceBrand(bg: 0xFF2D8CFF, fg: white)),
        ("figma", ServiceBrand(bg: 0xFFF24E1E, fg: white)),
        ("notion", ServiceBrand(bg: 0xFF000000, fg: white)),
        ("vercel", ServiceBrand(bg: 0xFF000000, fg: white)),
        ("shopify", ServiceBrand(bg: 0xFF96BF48, fg: white)),
        ("wordpress", ServiceBrand(bg: 0xFF21759B, fg: white)),
        ("okta", ServiceBrand(bg: 0xFF007DC1, fg: white)),
        ("epic", ServiceBrand(bg: 0xFF2F2D2E, fg: white)),
        ("nintendo", ServiceBrand(bg: 0xFFE60012, fg: white)),
        ("playstation", ServiceBrand(bg: 0xFF003791, fg: white)),
        ("xbox", ServiceBrand(bg: 0xFF107C10, fg: white)),
    ]

    /// The brand for an issuer, or nil. The returned brand always carries a letter: its own preset
    /// one, else the issuer's first character uppercased.
    public static func get(_ issuer: String) -> ServiceBrand? {
        // Blank / non-alphanumeric issuers must not match: an empty key is "contained" in every
        // brand name, which would hand out an arbitrary brand.
        let trimmed = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        let key = String(issuer.lowercased().unicodeScalars.filter {
            ("a"..."z").contains($0) || ("0"..."9").contains($0)
        })
        guard !key.isEmpty else { return nil }

        for (name, brand) in brands where key.contains(name) || name.contains(key) {
            return ServiceBrand(bg: brand.bg, fg: brand.fg, letter: brand.letter ?? String(first).uppercased())
        }
        return nil
    }
}
