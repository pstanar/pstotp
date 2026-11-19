import Foundation
import PsTotpCore
import Testing
@testable import PsTotp

/// A scripted server for the app tests (the package's `StubTransport` lives in its own test target).
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    struct Reply { var status = 200; var body = "{}" }
    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var paths: [String] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply = lock.withLock { () -> Reply in
            paths.append(request.url?.path ?? "")
            return replies.isEmpty ? Reply(status: 500) : replies.removeFirst()
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil,
                                   headerFields: ["Content-Type": "application/json"])!
        return (Data(reply.body.utf8), http)
    }
}

@MainActor
@Suite("AppModel connected mode")
struct AppModelConnectionTests {
    let db: AppDatabase
    let secrets = InMemorySecretStore()
    let biometrics = FakeBiometrics()
    private let strong = "Str0ng!Passw0rd"
    private let guid = "0f8fad5b-d9cb-469f-a165-70867728950e"
    private let salt = Data((1...16).map { UInt8($0) })

    init() throws { db = try AppDatabase.inMemory() }

    private func model(_ replies: [ScriptedTransport.Reply]) -> (AppModel, ScriptedTransport) {
        let transport = ScriptedTransport(replies)
        let repository = VaultRepository(db: db)
        let auth = AppModel.makeAuth(repository: repository, biometrics: biometrics, secrets: secrets, transport: transport)
        return (AppModel(repository: repository, iconLibrary: IconLibraryRepository(db: db), biometrics: biometrics, auth: auth), transport)
    }

    /// An unlocked vault with two accounts.
    private func unlockedModel(_ replies: [ScriptedTransport.Reply]) async -> (AppModel, ScriptedTransport) {
        let (model, transport) = model(replies)
        await model.start()
        _ = await model.setupPassword(strong, confirm: strong)
        _ = await model.addEntry(VaultEntryPlaintext(issuer: "GitHub", accountName: "me", secret: "JBSWY3DPEHPK3PXP"))
        _ = await model.addEntry(VaultEntryPlaintext(issuer: "AWS", accountName: "me", secret: "JBSWY3DPEHPK3PXP"))
        return (model, transport)
    }

    private func loginReplies(password: String, serverKey: Data) throws -> [ScriptedTransport.Reply] {
        let authKey = try Argon2.hash(password: password, salt: salt, memoryMb: 32, iterations: 2, parallelism: 1)
        let envelope = try EnvelopeHelper.encrypt(key: KeyDerivation.deriveEnvelopeKey(authKey: authKey), plaintext: serverKey)
        return [
            .init(body: """
            {"loginSessionId":"\(guid)","challenge":{"nonce":"AAAAAAAAAAAAAAAAAAAAAA==",
             "kdf":{"algorithm":"argon2id","memoryMb":32,"iterations":2,"parallelism":1,"salt":"\(salt.base64EncodedString())"}}}
            """),
            .init(body: """
            {"userId":"u1","accessToken":"AT","refreshToken":"RT","device":{"deviceId":"d1","status":"approved"},
             "envelopes":{"password":{"ciphertext":"\(envelope.ciphertext)","nonce":"\(envelope.nonce)","version":1}}}
            """),
            .init(),
        ]
    }

    @Test func connectingKeepsTheLocalAccountsReadable() async throws {
        let serverKey = KeyDerivation.generateVaultKey()
        let (model, _) = await unlockedModel(try loginReplies(password: "server pw", serverKey: serverKey))

        let outcome = await model.connect(serverUrl: "totp.example.com", email: " me@x.test ", password: "server pw")
        #expect(outcome == .connected)
        #expect(model.connection == .connected(serverUrl: "https://totp.example.com/api", email: "me@x.test"))
        #expect(model.entries.map(\.issuer) == ["GitHub", "AWS"])

        // A new launch finds the saved session.
        let relaunch = await restarted()
        #expect(relaunch.connection == .connected(serverUrl: "https://totp.example.com/api", email: "me@x.test"))
    }

    private func restarted() async -> AppModel {
        let (model, _) = model([])
        await model.start()
        return model
    }

    @Test func connectingTurnsOffTheBiometricCopyOfTheOldKey() async throws {
        let serverKey = KeyDerivation.generateVaultKey()
        let (model, _) = await unlockedModel(try loginReplies(password: "pw", serverKey: serverKey))
        #expect(await model.setBiometricEnabled(true) == nil)
        #expect(model.biometricEnabled)

        #expect(await model.connect(serverUrl: "x.test", email: "a@b.c", password: "pw") == .connected)
        #expect(!model.biometricEnabled)
        #expect(!biometrics.hasStoredKey())
    }

    @Test func invalidAddressIsRejectedBeforeAnyRequest() async {
        let (model, transport) = await unlockedModel([])
        #expect(await model.connect(serverUrl: "ftp://x", email: "a@b.c", password: "pw") == .failed("Enter a valid server address"))
        #expect(transport.paths.isEmpty)
    }

    @Test func serverErrorsAreShownAndNothingChanges() async {
        let (model, _) = await unlockedModel([.init(status: 401, body: #"{"detail":"Invalid credentials"}"#)])
        #expect(await model.connect(serverUrl: "x.test", email: "a@b.c", password: "bad") == .failed("Invalid credentials"))
        #expect(model.connection == .standalone)
        #expect(model.entries.count == 2)
    }

    @Test func pendingDeviceIsReportedNotConnected() async {
        let (model, _) = await unlockedModel([
            .init(body: #"{"loginSessionId":"\#(guid)","challenge":{"nonce":"AAAA","kdf":{"algorithm":"argon2id","memoryMb":32,"iterations":2,"parallelism":1,"salt":"AQIDBAUGBwgJCgsMDQ4PEA=="}}}"#),
            .init(body: #"{"userId":"u","accessToken":"AT","refreshToken":"RT","device":{"deviceId":"d","status":"pending"},"approvalRequestId":"r"}"#),
        ])
        #expect(await model.connect(serverUrl: "x.test", email: "a@b.c", password: "pw") == .pendingApproval)
        #expect(model.connection == .standalone)
    }

    @Test func registeringReturnsRecoveryCodesAndAdoptsTheNewKey() async throws {
        let (model, transport) = await unlockedModel([
            .init(body: #"{"registrationSessionId":"s1","emailVerificationRequired":true,"verificationCode":"123456"}"#),
            .init(body: #"{"verified":true}"#),
            .init(body: #"{"userId":"u1","deviceId":"d1","accessToken":"AT","refreshToken":"RT"}"#),
        ])
        guard case .started(let sessionId, let needsCode, let devCode) = await model.beginRegistration(serverUrl: "x.test", email: "a@b.c")
        else { Issue.record("registration didn't start"); return }
        #expect(needsCode && devCode == "123456")
        #expect(await model.verifyEmail(sessionId: sessionId, code: " 123456 ") == nil)

        guard case .success(let codes) = await model.register(serverUrl: "x.test", email: "a@b.c", password: "longenough", sessionId: sessionId)
        else { Issue.record("register failed"); return }
        #expect(codes.count == RecoveryCodes.count)
        #expect(model.connection == .connected(serverUrl: "https://x.test/api", email: "a@b.c"))
        #expect(model.entries.count == 2)
        // New entries are written under the new key and survive a relaunch + unlock with the new password.
        #expect(await model.addEntry(VaultEntryPlaintext(issuer: "New", accountName: "x", secret: "JBSWY3DPEHPK3PXP")) == nil)
        let relaunch = await restarted()
        #expect(await relaunch.unlock(password: "longenough"))
        #expect(relaunch.entries.map(\.issuer).sorted() == ["AWS", "GitHub", "New"])
        #expect(transport.paths == ["/api/auth/register/begin", "/api/auth/register/verify-email", "/api/auth/register"])
    }

    @Test func registerRejectsAShortPasswordWithoutContactingTheServer() async {
        let (model, transport) = await unlockedModel([])
        guard case .failure(let failure) = await model.register(serverUrl: "x.test", email: "a@b.c", password: "short", sessionId: nil)
        else { Issue.record("expected a failure"); return }
        #expect(failure.message == "Password must be at least 8 characters")
        #expect(transport.paths.isEmpty)
    }

    @Test func wrongEmailCodeIsReported() async {
        let (model, _) = await unlockedModel([.init(body: #"{"verified":false}"#)])
        #expect(await model.verifyEmail(sessionId: "s", code: "000000") == "Invalid verification code")
    }

    @Test func disconnectingReturnsToStandaloneAndKeepsTheAccounts() async throws {
        let serverKey = KeyDerivation.generateVaultKey()
        let (model, _) = await unlockedModel(try loginReplies(password: "pw", serverKey: serverKey) + [.init()])
        _ = await model.connect(serverUrl: "x.test", email: "a@b.c", password: "pw")
        await model.disconnect()
        #expect(model.connection == .standalone)
        #expect(model.entries.count == 2)
        #expect(await restarted().connection == .standalone)
    }

    @Test func freshInstallClearsSecretsLeftByAnEarlierInstall() async throws {
        try secrets.setAll([.accessToken: "old", .refreshToken: "old", .ecdhPrivateKey: "old"])
        let (model, _) = model([])
        await model.start()
        #expect(model.phase == .needsSetup)
        for key in SecretKey.allCases { #expect(try secrets.get(key) == nil) }
    }
}
