import Foundation

/// Turning scanned QR payloads into entries.
///
/// Like Android, only `otpauth://` codes are accepted — Google Authenticator's
/// `otpauth-migration://` export QR codes are imported from a file/URI paste, not scanned.
public enum QRImport {

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case unreadableImage
        case noQRCode

        public var description: String {
            switch self {
            case .unreadableImage: "Failed to load image"
            case .noQRCode: "No QR code found in image"
            }
        }
    }

    /// The first `otpauth://` payload among `codes`, parsed and validated.
    /// Unlike Android's photo import, every code in the image is considered, not just the first.
    public static func entry(fromCodes codes: [String]) throws -> VaultEntryPlaintext {
        guard let uri = codes.first(where: { $0.hasPrefix("otpauth://") }) else { throw Failure.noQRCode }
        return try EntryValidation.validated(try OtpauthUri.parse(uri.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    /// Decode a picked photo / screenshot and read the account from it.
    public static func entry(fromImageData data: Data) throws -> VaultEntryPlaintext {
        guard let image = QRCode.image(from: data) else { throw Failure.unreadableImage }
        return try entry(fromCodes: QRCode.decode(image))
    }
}

/// Drops repeats of the same scanned value so a camera that sees one QR code in thirty consecutive
/// frames reports it once. (Android instead stops scanning after the first hit, which also stops it
/// recovering from an invalid code.)
public struct ScanDebouncer: Sendable {
    public let interval: TimeInterval
    private var lastValue: String?
    private var lastHandledAt: Date = .distantPast

    public init(interval: TimeInterval = 2) { self.interval = interval }

    /// True when `value` should be handled now; records it when so.
    public mutating func shouldHandle(_ value: String, at now: Date = Date()) -> Bool {
        if value == lastValue, now.timeIntervalSince(lastHandledAt) < interval { return false }
        lastValue = value
        lastHandledAt = now
        return true
    }
}
