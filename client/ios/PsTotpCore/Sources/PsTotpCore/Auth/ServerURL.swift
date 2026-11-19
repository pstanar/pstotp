import Foundation

/// Cleans up the server address a user typed into the Connect screen.
public enum ServerURL {
    /// - Returns: the API base URL without trailing slash, or nil when it isn't a usable http(s) address.
    ///
    /// A missing scheme becomes `https://`; a bare host gets the server's `/api` path (the API is
    /// always served under it, so `totp.example.com` works as well as `https://totp.example.com/api`).
    public static func normalize(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        components.scheme = scheme
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path.isEmpty ? "/api" : path
        return components.string
    }

    /// `totp.example.com` for display.
    public static func displayHost(_ url: String) -> String {
        URLComponents(string: url)?.host ?? url
    }
}
