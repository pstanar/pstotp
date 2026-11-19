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
    /// Status for the vault endpoints, which are answered automatically (an empty, accepting vault)
    /// and don't use up scripted replies.
    var vaultStatus = 200

    init(_ replies: [Reply]) { self.replies = replies }

    /// Everything the test script isn't about: the requests a sync makes.
    var vaultPaths: [String] { lock.withLock { paths.filter { $0.hasPrefix("/api/vault") } } }
    var authPaths: [String] { lock.withLock { paths.filter { !$0.hasPrefix("/api/vault") } } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        let reply = lock.withLock { () -> Reply in
            paths.append(path)
            if path.hasPrefix("/api/vault") {
                if vaultStatus != 200 { return Reply(status: vaultStatus) }
                switch request.httpMethod {
                case "GET": return Reply(body: #"{"entries":[],"serverTime":"2026-11-19T12:00:00Z"}"#)
                case "PUT": return Reply(body: #"{"id":"x","entryVersion":1,"updatedAt":"2026-11-19T10:00:00Z"}"#)
                default: return Reply()
                }
            }
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
        let server = AppModel.makeServerSession(db: db, repository: repository, biometrics: biometrics, secrets: secrets, transport: transport)
        return (AppModel(repository: repository, iconLibrary: IconLibraryRepository(db: db), biometrics: biometrics, server: server), transport)
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
        #expect(transport.authPaths == ["/api/auth/register/begin", "/api/auth/register/verify-email", "/api/auth/register"])
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

    // MARK: Sync

    @Test func connectingPushesTheLocalAccountsAndRecordsTheSyncTime() async throws {
        let (model, transport) = await unlockedModel(try loginReplies(password: "pw", serverKey: KeyDerivation.generateVaultKey()))
        #expect(await model.connect(serverUrl: "x.test", email: "a@b.c", password: "pw") == .connected)
        await model.waitForPendingSync()
        #expect(transport.vaultPaths.filter { $0.hasPrefix("/api/vault/") && $0 != "/api/vault/reorder" }.count == 2)   // two PUTs
        #expect(transport.vaultPaths.contains("/api/vault/reorder") && transport.vaultPaths.contains("/api/vault"))
        #expect(model.lastSyncAt == "2026-11-19T12:00:00Z")
        #expect(model.syncState == .idle)
    }

    @Test func editsAreSyncedAsTheyHappen() async throws {
        let (model, transport) = await unlockedModel(try loginReplies(password: "pw", serverKey: KeyDerivation.generateVaultKey()))
        _ = await model.connect(serverUrl: "x.test", email: "a@b.c", password: "pw")
        await model.waitForPendingSync()
        let before = transport.vaultPaths.count

        #expect(await model.addEntry(VaultEntryPlaintext(issuer: "New", accountName: "x", secret: "JBSWY3DPEHPK3PXP")) == nil)
        await model.waitForPendingSync()
        #expect(transport.vaultPaths.count > before)
        #expect(transport.vaultPaths.last == "/api/vault")   // push, order, then pull
    }

    @Test func standaloneNeverTouchesTheNetwork() async {
        let (model, transport) = await unlockedModel([])
        _ = await model.addEntry(VaultEntryPlaintext(issuer: "New", accountName: "x", secret: "JBSWY3DPEHPK3PXP"))
        await model.syncNow()
        #expect(transport.paths.isEmpty)
        #expect(model.syncState == .idle)
    }

    @Test func aFailedSyncIsShownAndRetriedByTheNextOne() async throws {
        let (model, transport) = await unlockedModel(try loginReplies(password: "pw", serverKey: KeyDerivation.generateVaultKey()))
        transport.vaultStatus = 500
        _ = await model.connect(serverUrl: "x.test", email: "a@b.c", password: "pw")
        await model.waitForPendingSync()
        #expect(model.syncState == .failed("Server error (HTTP 500)"))
        #expect(model.connection != .standalone)

        transport.vaultStatus = 200
        await model.syncNow()
        #expect(model.syncState == .idle)
    }

    @Test func anExpiredSessionAsksForANewSignIn() async throws {
        let (model, transport) = await unlockedModel(try loginReplies(password: "pw", serverKey: KeyDerivation.generateVaultKey()) + [.init(status: 401)])
        transport.vaultStatus = 401
        _ = await model.connect(serverUrl: "x.test", email: " a@b.c", password: "pw")
        await model.waitForPendingSync()
        #expect(model.connection == .expired(serverUrl: "https://x.test/api", email: "a@b.c"))
        #expect(model.syncState == .idle)
        #expect(model.entries.count == 2)   // nothing lost
    }

    @Test func disconnectingForgetsTheSyncTime() async throws {
        let (model, _) = await unlockedModel(try loginReplies(password: "pw", serverKey: KeyDerivation.generateVaultKey()) + [.init()])
        _ = await model.connect(serverUrl: "x.test", email: "a@b.c", password: "pw")
        await model.waitForPendingSync()
        await model.disconnect()
        #expect(model.lastSyncAt == nil && model.syncState == .idle)
    }
}
