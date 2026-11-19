import Foundation

/// Decodes from any body (including an empty one) — for endpoints whose response is ignored.
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
    public init(from decoder: Decoder) throws {}
}

/// HTTP client with Bearer-token management (mirrors Android's `ApiClient`).
///
/// - Adds `Authorization` on authenticated requests.
/// - On 401: refreshes the tokens (concurrent callers share one refresh) and retries once.
/// - Refresh refused (400 / 401 / 403) → `ApiError.sessionExpired` and the tokens are cleared; any other
///   failure of the refresh (unreachable server, 5xx, 429) is passed on and the tokens are kept, so the
///   user can retry.
public actor ApiClient {
    /// Base URL without trailing slash, e.g. `https://totp.example.com/api`.
    public private(set) var baseURL: String
    public private(set) var accessToken: String?
    public private(set) var refreshToken: String?

    private let transport: HTTPTransport
    private var refreshTask: Task<Void, Error>?
    private var onTokensRefreshed: (@Sendable (_ access: String, _ refresh: String) -> Void)?

    public init(baseURL: String, transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = Self.normalized(baseURL)
        self.transport = transport
    }

    private static func normalized(_ url: String) -> String {
        var url = url
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }

    public func setBaseURL(_ url: String) { baseURL = Self.normalized(url) }

    public func setTokens(access: String?, refresh: String?) {
        accessToken = access
        refreshToken = refresh
    }

    public func clearTokens() { setTokens(access: nil, refresh: nil) }

    public var hasTokens: Bool { accessToken != nil && refreshToken != nil }

    /// Called after a successful refresh so the owner can persist the new tokens.
    public func setOnTokensRefreshed(_ handler: (@Sendable (_ access: String, _ refresh: String) -> Void)?) {
        onTokensRefreshed = handler
    }

    // MARK: HTTP verbs

    public func get<T: Decodable & Sendable>(_ endpoint: String) async throws -> T {
        try await executeWithAuth("GET", endpoint, body: nil)
    }

    public func post<T: Decodable & Sendable>(_ endpoint: String, body: (any Encodable & Sendable)? = nil) async throws -> T {
        try await executeWithAuth("POST", endpoint, body: body)
    }

    public func put<T: Decodable & Sendable>(_ endpoint: String, body: (any Encodable & Sendable)? = nil) async throws -> T {
        try await executeWithAuth("PUT", endpoint, body: body)
    }

    public func delete(_ endpoint: String) async throws {
        let _: EmptyResponse = try await executeWithAuth("DELETE", endpoint, body: nil)
    }

    /// POST without auth (login challenge, register, …).
    public func postPublic<T: Decodable & Sendable>(_ endpoint: String, body: (any Encodable & Sendable)? = nil) async throws -> T {
        try await execute("POST", endpoint, body: body, auth: false)
    }

    // MARK: Internals

    private func executeWithAuth<T: Decodable & Sendable>(
        _ method: String, _ endpoint: String, body: (any Encodable & Sendable)?
    ) async throws -> T {
        let tokenUsed = accessToken
        do {
            return try await execute(method, endpoint, body: body, auth: true)
        } catch ApiError.http(401, _) {
            try await refreshTokens(rejected: tokenUsed)
            return try await execute(method, endpoint, body: body, auth: true)
        }
    }

    /// `rejected` is the access token the failed request carried: if another caller already
    /// replaced it, that refresh is enough and we don't burn a second refresh token.
    private func refreshTokens(rejected: String?) async throws {
        if let refreshTask {
            try await refreshTask.value
            return
        }
        if accessToken != rejected { return }
        guard let refreshToken else { throw ApiError.sessionExpired }

        let task = Task { try await self.performRefresh(refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private func performRefresh(_ token: String) async throws {
        struct Request: Encodable, Sendable { let refreshToken: String }
        do {
            let response: RefreshResponse = try await execute(
                "POST", "/auth/refresh", body: Request(refreshToken: token), auth: false)
            accessToken = response.accessToken
            refreshToken = response.refreshToken
            if let access = response.accessToken, let refresh = response.refreshToken {
                onTokensRefreshed?(access, refresh)
            }
        } catch let error as ApiError {
            // Only a refusal of the token ends the session. An unreachable server, a 5xx from the server or
            // a proxy in front of it, or a 429 says nothing about the tokens: keep them and let the caller retry.
            guard case .http(let status, _) = error, [400, 401, 403].contains(status) else { throw error }
            clearTokens()
            throw ApiError.sessionExpired
        }
    }

    private func execute<T: Decodable & Sendable>(
        _ method: String, _ endpoint: String, body: (any Encodable & Sendable)?, auth: Bool
    ) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw ApiError.network("Invalid server URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        } else if method == "POST" || method == "PUT" {
            request.httpBody = Data()
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        if auth, let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw ApiError.network(ApiErrorMessages.network(error))
        }

        guard (200..<300).contains(response.statusCode) else {
            let message = ApiErrorMessages.build(
                statusCode: response.statusCode,
                contentType: response.value(forHTTPHeaderField: "Content-Type"),
                body: data)
            throw response.statusCode == 409
                ? ApiError.conflict(message)
                : ApiError.http(status: response.statusCode, message: message)
        }

        let payload = data.allSatisfy { $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }
            ? Data("{}".utf8) : data
        do {
            return try JSONDecoder().decode(T.self, from: payload)
        } catch {
            throw ApiError.http(status: response.statusCode, message: "Unexpected response from the server.")
        }
    }
}
