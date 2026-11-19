import Foundation
import Testing
@testable import PsTotpCore

/// Scripted server: each request is recorded and answered by the next handler result.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Reply { var status: Int = 200; var body: String = "{}"; var contentType = "application/json"; var error: Error? }
    private let lock = NSLock()
    private var replies: [Reply]
    private var _requests: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { _requests } }
    /// Delay each reply, so concurrent callers overlap.
    var delayNanos: UInt64 = 0

    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = lock.withLock {
            _requests.append(request)
            return replies.isEmpty ? Reply(status: 500, body: "{}") : replies.removeFirst()
        }
        if delayNanos > 0 { try? await Task.sleep(nanoseconds: delayNanos) }
        if let error = reply.error { throw error }
        let http = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil,
                                   headerFields: ["Content-Type": reply.contentType])!
        return (Data(reply.body.utf8), http)
    }
}

private func body(_ request: URLRequest) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
}

@Suite struct ApiClientTests {
    @Test func trailingSlashesAreTrimmedAndBearerIsSent() async throws {
        let stub = StubTransport([.init(body: #"{"entries":[],"serverTime":"t"}"#)])
        let client = ApiClient(baseURL: "https://x.test/api//", transport: stub)
        await client.setTokens(access: "AT", refresh: "RT")
        let response = try await VaultApi(client: client).fetchVault()
        #expect(response.serverTime == "t")
        #expect(stub.requests[0].url?.absoluteString == "https://x.test/api/vault")
        #expect(stub.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer AT")
    }

    @Test func publicCallsCarryNoAuthorization() async throws {
        let stub = StubTransport([.init(body: #"{"registrationSessionId":"s","emailVerificationRequired":true,"verificationCode":""}"#)])
        let client = ApiClient(baseURL: "https://x.test/api", transport: stub)
        await client.setTokens(access: "AT", refresh: "RT")
        let response = try await AuthApi(client: client).registerBegin(email: "a@b.c")
        #expect(response.verificationCode == nil)   // "" → nil
        #expect(stub.requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(body(stub.requests[0])["email"] as? String == "a@b.c")
    }

    @Test func refreshesOn401AndRetriesOnce() async throws {
        let stub = StubTransport([
            .init(status: 401, body: "{}"),
            .init(body: #"{"accessToken":"AT2","refreshToken":"RT2"}"#),
            .init(body: #"{"entries":[],"serverTime":"t"}"#),
        ])
        let client = ApiClient(baseURL: "https://x.test/api", transport: stub)
        await client.setTokens(access: "AT", refresh: "RT")
        let saved = LockedBox<[String]>([])
        await client.setOnTokensRefreshed { a, r in saved.set([a, r]) }
        _ = try await VaultApi(client: client).fetchVault()
        let urls = stub.requests.map { $0.url!.path }
        #expect(urls == ["/api/vault", "/api/auth/refresh", "/api/vault"])
        #expect(body(stub.requests[1])["refreshToken"] as? String == "RT")
        #expect(stub.requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer AT2")
        #expect(saved.get() == ["AT2", "RT2"])
        #expect(await client.refreshToken == "RT2")
    }

    @Test func rejectedRefreshClearsTokensAndExpiresSession() async throws {
        let stub = StubTransport([.init(status: 401), .init(status: 401)])
        let client = ApiClient(baseURL: "https://x.test/api", transport: stub)
        await client.setTokens(access: "AT", refresh: "RT")
        await #expect(throws: ApiError.sessionExpired) { _ = try await VaultApi(client: client).fetchVault() }
        #expect(await client.hasTokens == false)
    }

    @Test func unreachableServerDuringRefreshKeepsTokens() async throws {
        let stub = StubTransport([.init(status: 401), .init(error: URLError(.notConnectedToInternet))])
        let client = ApiClient(baseURL: "https://x.test/api", transport: stub)
        await client.setTokens(access: "AT", refresh: "RT")
        await #expect(throws: ApiError.network("Could not reach the server.")) { _ = try await VaultApi(client: client).fetchVault() }
        #expect(await client.hasTokens)
    }

    @Test func concurrentUnauthorizedCallsShareOneRefresh() async throws {
        let ok = #"{"entries":[],"serverTime":"t"}"#
        let stub = StubTransport([
            .init(status: 401), .init(status: 401),
            .init(body: #"{"accessToken":"AT2","refreshToken":"RT2"}"#),
            .init(body: ok), .init(body: ok),
        ])
        stub.delayNanos = 20_000_000
        let client = ApiClient(baseURL: "https://x.test/api", transport: stub)
        await client.setTokens(access: "AT", refresh: "RT")
        let api = VaultApi(client: client)
        async let a = api.fetchVault()
        async let b = api.fetchVault()
        _ = try await (a, b)
        #expect(stub.requests.filter { $0.url!.path.hasSuffix("/auth/refresh") }.count == 1)
    }

    @Test func conflictAndDetailMessages() async throws {
        let stub = StubTransport([
            .init(status: 409, body: #"{"detail":"Version conflict on entry"}"#),
            .init(status: 400, body: #"{"detail":"Email already registered"}"#),
        ])
        let client = ApiClient(baseURL: "https://x.test/api", transport: stub)
        await client.setTokens(access: "AT", refresh: "RT")
        await #expect(throws: ApiError.conflict("Version conflict on entry")) {
            _ = try await VaultApi(client: client).upsertEntry(entryId: "e", entryPayload: "p", entryVersion: 1)
        }
        await #expect(throws: ApiError.http(status: 400, message: "Email already registered")) {
            _ = try await AuthApi(client: client).registerBegin(email: "x")
        }
    }

    @Test func errorMessagesNeverLeakHtmlBodies() {
        let html = Data("<html>502 Bad Gateway nginx</html>".utf8)
        #expect(ApiErrorMessages.build(statusCode: 502, contentType: "text/html", body: html) == "Service unavailable (HTTP 502)")
        #expect(ApiErrorMessages.build(statusCode: 418, contentType: nil, body: html) == "Server returned HTTP 418")
        #expect(ApiErrorMessages.build(statusCode: 404, contentType: "application/json", body: Data("{}".utf8)) == "Not found (HTTP 404)")
        #expect(ApiErrorMessages.build(statusCode: 500, contentType: nil, body: Data(#"  {"detail":"boom"}"#.utf8)) == "boom")
    }

    @Test func networkFailuresAreFriendly() async throws {
        let stub = StubTransport([.init(error: URLError(.cannotFindHost))])
        let client = ApiClient(baseURL: "https://x.test/api", transport: stub)
        await #expect(throws: ApiError.network("Server not found. Check the URL and your connection.")) {
            _ = try await AuthApi(client: client).registerBegin(email: "x")
        }
    }

    @Test func deleteAndEmptyBodiesSucceed() async throws {
        let stub = StubTransport([.init(status: 204, body: ""), .init(status: 200, body: "")])
        let client = ApiClient(baseURL: "https://x.test/api", transport: stub)
        await client.setTokens(access: "AT", refresh: "RT")
        try await VaultApi(client: client).deleteEntry(entryId: "e1")
        try await DevicesApi(client: client).rejectDevice(deviceId: "d1")
        #expect(stub.requests.map(\.httpMethod) == ["DELETE", "POST"])
        #expect(stub.requests[0].httpBody == nil)
    }
}

@Suite struct ApiModelTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func loginCompleteDefaultsAndEmptyTokens() throws {
        let r = try decode(LoginCompleteResponse.self, """
        {"userId":"u","accessToken":"","refreshToken":null,"device":{"deviceId":"d","status":"pending"},
         "envelopes":{"password":{"ciphertext":"c","nonce":"n","version":1},"device":null},"approvalRequestId":"a"}
        """)
        #expect(r.accessToken == nil && r.refreshToken == nil)
        #expect(r.device.persistentKeyAllowed == false && r.forcePasswordReset == false)
        #expect(r.envelopes?.password == Envelope(ciphertext: "c", nonce: "n"))
        #expect(r.envelopes?.device == nil)
        #expect(r.approvalRequestId == "a" && r.role == nil)
    }

    @Test func vaultEntryDefaults() throws {
        let r = try decode(VaultSyncResponse.self, """
        {"entries":[{"id":"i","entryPayload":"p","entryVersion":2,"deletedAt":null,"updatedAt":"u"}],"serverTime":"s"}
        """)
        #expect(r.entries[0].sortOrder == 0 && r.entries[0].deletedAt == nil && r.entries[0].entryVersion == 2)
    }

    @Test func iconLibraryEmptyRow() throws {
        let r = try decode(IconLibraryResponse.self, "{}")
        #expect(r.encryptedPayload == "" && r.version == 0 && r.updatedAt == nil)
    }

    @Test func webAuthnOptionsKeepStructure() throws {
        let r = try decode(WebAuthnBeginResponse.self, #"{"ceremonyId":"c","publicKeyOptions":{"challenge":"abc","rp":{"id":"x.test"},"timeout":60000}}"#)
        let echoed = try JSONValue(jsonString: r.publicKeyOptionsJson)
        guard case .object(let o) = echoed, case .object(let rp)? = o["rp"] else { Issue.record("not an object"); return }
        #expect(o["challenge"] == .string("abc") && rp["id"] == .string("x.test") && o["timeout"] == .number(60000))
    }

    @Test func requestShapesMatchTheWireFormat() throws {
        let register = DeviceDto.ios(publicKeyBase64: "PK")
        let data = try JSONEncoder().encode(register)
        let o = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(o["clientType"] as? String == "ios" && o["platform"] as? String == "ios" && o["devicePublicKey"] as? String == "PK")

        let recovery = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            RecoveryDto(recoveryEnvelopeCiphertext: "c", recoveryEnvelopeNonce: "n", recoveryCodeHashes: ["h"]))) as? [String: Any]
        #expect(recovery?["recoveryCodeSalt"] == nil)          // omitted when nil, like Android
        #expect(recovery?["recoveryEnvelopeVersion"] as? Int == 1)

        let kdf = KdfConfig.default(saltBase64: "S")
        #expect(kdf == KdfConfig(algorithm: "argon2id", memoryMb: 64, iterations: 3, parallelism: 4, salt: "S"))
    }
}

final class LockedBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T { lock.withLock { value } }
    func set(_ new: T) { lock.withLock { value = new } }
}
