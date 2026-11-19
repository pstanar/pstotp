import Foundation

/// Errors from the server API, mirroring Android's ApiException hierarchy.
public enum ApiError: Error, Equatable, LocalizedError, Sendable {
    /// Non-success HTTP status (other than 409). 401 here means "token rejected".
    case http(status: Int, message: String)
    /// 409 — version mismatch on a vault entry / icon library write.
    case conflict(String)
    /// The refresh token was rejected; the user must log in again.
    case sessionExpired
    /// The server was never reached (DNS, timeout, TLS…). The message is already user-friendly.
    case network(String)

    public var statusCode: Int? {
        switch self {
        case .http(let status, _): status
        case .conflict: 409
        case .sessionExpired: 401
        case .network: nil
        }
    }

    public var message: String {
        switch self {
        case .http(_, let message), .conflict(let message), .network(let message): message
        case .sessionExpired: "Session expired — please log in again"
        }
    }

    public var errorDescription: String? { message }
}

enum ApiErrorMessages {
    /// User-facing message for a non-success response. Uses the JSON `detail` field when the body
    /// is JSON, otherwise a status-based message — never raw body text, so reverse-proxy HTML
    /// error pages can't leak into the UI.
    static func build(statusCode: Int, contentType: String?, body: Data) -> String {
        let text = String(data: body, encoding: .utf8) ?? ""
        let looksLikeJSON = (contentType?.lowercased().contains("json") ?? false)
            || text.drop(while: \.isWhitespace).hasPrefix("{")
        if looksLikeJSON, !text.isEmpty,
           let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
           let detail = object["detail"] as? String, !detail.isEmpty {
            return detail
        }
        switch statusCode {
        case 400: return "Bad request (HTTP 400)"
        case 403: return "Access denied (HTTP 403)"
        case 404: return "Not found (HTTP 404)"
        case 500: return "Server error (HTTP 500)"
        case 502, 503: return "Service unavailable (HTTP \(statusCode))"
        case 504: return "Server did not respond in time (HTTP 504)"
        default: return "Server returned HTTP \(statusCode)"
        }
    }

    static func network(_ error: Error) -> String {
        guard let urlError = error as? URLError else {
            let text = error.localizedDescription
            return text.isEmpty ? "Network error" : text
        }
        switch urlError.code {
        case .cannotFindHost, .dnsLookupFailed: return "Server not found. Check the URL and your connection."
        case .timedOut: return "Server did not respond in time."
        case .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost:
            return "Could not reach the server."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .appTransportSecurityRequiresSecureConnection:
            return "Secure connection failed (TLS/certificate issue)."
        default:
            let text = urlError.localizedDescription
            return text.isEmpty ? "Network error" : text
        }
    }
}
