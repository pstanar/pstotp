import Foundation

/// Lenient accessors over `JSONSerialization` objects, mirroring org.json's `optX` semantics
/// that the Android importers rely on (missing/mistyped → default, never throw).
typealias JSONObject = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func optString(_ key: String, _ fallback: String = "") -> String {
        switch self[key] {
        case let s as String: s
        case let n as NSNumber: n.stringValue
        default: fallback
        }
    }

    /// A string value only when it really is a non-empty string.
    func optStringField(_ key: String) -> String? {
        (self[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    func optInt(_ key: String, _ fallback: Int) -> Int {
        switch self[key] {
        case let n as NSNumber: n.intValue
        case let s as String: Int(s) ?? fallback
        default: fallback
        }
    }

    func optObject(_ key: String) -> JSONObject? { self[key] as? JSONObject }
    func optArray(_ key: String) -> [Any]? { self[key] as? [Any] }
    func has(_ key: String) -> Bool { self[key] != nil }
}
