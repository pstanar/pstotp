import Foundation

/// One custom icon in the user's library. `data` is a 64×64 PNG data URL (the format
/// `VaultEntryPlaintext.icon` accepts). Counterpart of Android's `LibraryIcon`; the JSON shape must
/// match the web client's so a blob written by either decrypts on the other.
public struct LibraryIcon: Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var data: String
    public var createdAt: String
    /// De-duplication fingerprints. Both optional: legacy blobs predate them. `dataHash` hashes the
    /// data URL string; `sourceHash` the original pre-resize bytes. Omitted from JSON when nil.
    public var dataHash: String?
    public var sourceHash: String?

    public init(
        id: String, label: String, data: String, createdAt: String,
        dataHash: String? = nil, sourceHash: String? = nil
    ) {
        self.id = id
        self.label = label
        self.data = data
        self.createdAt = createdAt
        self.dataHash = dataHash
        self.sourceHash = sourceHash
    }

    /// Lenient like Android's `fromJson`: a missing label becomes "Icon", empty hashes become nil.
    /// Nil when `id` or `data` is missing.
    init?(json: JSONObject) {
        guard let id = json["id"] as? String, let data = json["data"] as? String else { return nil }
        self.init(
            id: id,
            label: json.optStringField("label") ?? "Icon",
            data: data,
            createdAt: json.optString("createdAt"),
            dataHash: json.optStringField("dataHash"),
            sourceHash: json.optStringField("sourceHash"))
    }

    var json: JSONObject {
        var object: JSONObject = ["id": id, "label": label, "data": data, "createdAt": createdAt]
        if let dataHash { object["dataHash"] = dataHash }
        if let sourceHash { object["sourceHash"] = sourceHash }
        return object
    }
}

/// The decrypted library. `version` is the blob-format version.
public struct IconLibraryBlob: Equatable, Sendable {
    public var version: Int
    public var icons: [LibraryIcon]

    public init(version: Int = 1, icons: [LibraryIcon] = []) {
        self.version = version
        self.icons = icons
    }

    public init(jsonData: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: jsonData) as? JSONObject else {
            throw IconLibraryError.malformedBlob
        }
        self.init(
            version: object.optInt("version", 1),
            icons: (object.optArray("icons") ?? []).compactMap { ($0 as? JSONObject).flatMap(LibraryIcon.init(json:)) })
    }

    /// UTF-8 JSON, slashes unescaped like `JSON.stringify` so the size matches the other clients'.
    public func jsonData() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: ["version": version, "icons": icons.map(\.json)] as JSONObject,
            options: [.withoutEscapingSlashes])
    }
}

public enum IconLibraryError: Error, Equatable, CustomStringConvertible {
    case malformedBlob
    case countCapExceeded
    case byteCapExceeded

    public var description: String {
        switch self {
        case .malformedBlob: "The icon library is damaged"
        case .countCapExceeded: "Icon library is full (\(IconLibraryLimits.maxIcons) max). Delete some icons first."
        case .byteCapExceeded: "Icon library is full (size limit). Delete some icons first."
        }
    }
}

/// Per-user caps, as on the web client. The server rejects any encrypted blob over 2 MB.
public enum IconLibraryLimits {
    public static let maxIcons = 100
    public static let maxBytes = 2 * 1024 * 1024
}

/// Encrypt / decrypt the library blob with the vault key: AES-256-GCM, AAD `pstotp-icon-library-v1`,
/// nonce(12) || ciphertext+tag(16). Byte-compatible with the web and Android clients.
public enum IconLibraryCrypto {
    private static let associatedData = Data("pstotp-icon-library-v1".utf8)

    public static func encrypt(vaultKey: Data, blob: IconLibraryBlob) throws -> Data {
        try AesGcm.encrypt(key: vaultKey, plaintext: blob.jsonData(), associatedData: associatedData)
    }

    public static func decrypt(vaultKey: Data, payload: Data) throws -> IconLibraryBlob {
        try IconLibraryBlob(jsonData: AesGcm.decrypt(key: vaultKey, payload: payload, associatedData: associatedData))
    }
}
