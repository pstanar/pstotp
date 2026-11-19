import Foundation

extension StringProtocol {
    public var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    public var isBlank: Bool { trimmed.isEmpty }
}
