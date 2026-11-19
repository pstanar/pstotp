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
    /// Status for the icon-library endpoint (an empty library on the server).
    var iconStatus = 200
    /// What GET /devices returns, and the status for device actions.
    var devicesBody = #"{"devices":[]}"#
    var deviceActionStatus = 200
    /// What GET /security/audit-events returns, and its status.
    var auditBody = #"{"events":[]}"#
    var auditStatus = 200
    private(set) var auditPaths: [String] = []
    /// "METHOD /path" for every /devices request.
    private(set) var deviceRequests: [String] = []
    private(set) var lastDeviceBody: Data?

    init(_ replies: [Reply]) { self.replies = replies }

    /// Everything the test script isn't about: the requests a sync makes.
    var vaultPaths: [String] { lock.withLock { paths.filter { $0.hasPrefix("/api/vault") && $0 != Self.iconPath } } }
    var authPaths: [String] { lock.withLock { paths.filter { !$0.hasPrefix("/api/vault") } } }
    /// One entry per request to the icon-library endpoint, as "GET" / "PUT".
    private(set) var iconRequests: [String] = []
    static let iconPath = "/api/vault/icon-library"

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        let reply = lock.withLock { () -> Reply in
            paths.append(path)
            if path == "/api/security/audit-events" {
                auditPaths.append(request.url?.absoluteString ?? "")
                return auditStatus == 200 ? Reply(body: auditBody) : Reply(status: auditStatus)
            }
            if path.hasPrefix("/api/devices") && path != "/api/devices/self/envelope" {
                deviceRequests.append("\(request.httpMethod ?? "") \(path.dropFirst("/api".count))")
                lastDeviceBody = request.httpBody
                if request.httpMethod == "GET" { return Reply(body: devicesBody) }
                return Reply(status: deviceActionStatus)
            }
            if path == Self.iconPath {
                iconRequests.append(request.httpMethod ?? "")
                if iconStatus != 200 { return Reply(status: iconStatus) }
                return request.httpMethod == "GET"
                    ? Reply(body: #"{"encryptedPayload":"","version":0}"#)
                    : Reply(body: #"{"version":1,"updatedAt":"2026-11-19T10:00:00Z"}"#)
            }
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

    // MARK: Icon library

    private let iconData = "data:image/png;base64,AAAA"

    @Test func connectingPushesTheLocalIconLibrary() async throws {
        let (model, transport) = await unlockedModel(try loginReplies(password: "pw", serverKey: KeyDerivation.generateVaultKey()))
        #expect(await model.addLibraryIcon(label: "Mine", dataUrl: iconData, source: nil) == nil)
        #expect(model.libraryIcons.count == 1)

        _ = await model.connect(serverUrl: "x.test", email: "a@b.c", password: "pw")
        await model.waitForPendingSync()
        // The server had none, so ours is created there.
        #expect(transport.iconRequests == ["GET", "PUT"])
        #expect(model.libraryIcons.map(\.label) == ["Mine"])
        #expect(model.syncState == .idle)
    }

    @Test func connectedLibraryEditsGoToTheServer() async throws {
        let (model, transport) = await unlockedModel(try loginReplies(password: "pw", serverKey: KeyDerivation.generateVaultKey()))
        _ = await model.connect(serverUrl: "x.test", email: "a@b.c", password: "pw")
        await model.waitForPendingSync()
        let before = transport.iconRequests.count

        #expect(await model.addLibraryIcon(label: "New", dataUrl: iconData, source: nil) == nil)
        await model.waitForPendingSync()
        #expect(transport.iconRequests.count > before)
        #expect(transport.iconRequests.last == "PUT")
        #expect(model.libraryIcons.map(\.label) == ["New"])
    }

    @Test func aLibraryEditIsRefusedWhenTheServerCopyCantBeFetched() async throws {
        let (model, transport) = await unlockedModel(try loginReplies(password: "pw", serverKey: KeyDerivation.generateVaultKey()))
        transport.iconStatus = 500
        _ = await model.connect(serverUrl: "x.test", email: "a@b.c", password: "pw")
        await model.waitForPendingSync()
        #expect(model.syncState == .failed("Couldn't sync My icons: Server error (HTTP 500)"))

        // Fail closed: editing from an unreconciled local copy could overwrite the account's library.
        #expect(await model.addLibraryIcon(label: "X", dataUrl: iconData, source: nil)
                == "Couldn't sync icon library — check your connection and try again.")
        #expect(await model.removeLibraryIcon(id: "any") == "Couldn't sync icon library — check your connection and try again.")
        #expect(model.libraryIcons.isEmpty)
        #expect(!transport.iconRequests.contains("PUT"))

        transport.iconStatus = 200
        #expect(await model.addLibraryIcon(label: "X", dataUrl: iconData, source: nil) == nil)
    }

    @Test func standaloneLibraryEditsNeverTouchTheNetwork() async {
        let (model, transport) = await unlockedModel([])
        #expect(await model.addLibraryIcon(label: "Mine", dataUrl: iconData, source: nil) == nil)
        await model.waitForPendingSync()
        #expect(transport.paths.isEmpty)
    }

    // MARK: Change password

    private func connectedModel(password: String = "pw", extra: [ScriptedTransport.Reply]) async throws -> (AppModel, ScriptedTransport) {
        let replies = try loginReplies(password: password, serverKey: KeyDerivation.generateVaultKey())
        let (model, transport) = await unlockedModel(replies + extra)
        _ = await model.connect(serverUrl: "x.test", email: "a@b.c", password: password)
        await model.waitForPendingSync()
        return (model, transport)
    }

    @Test func changingThePasswordSucceedsAndTheNewOneUnlocksTheVault() async throws {
        let challenge = try loginReplies(password: "pw", serverKey: KeyDerivation.generateVaultKey())[0]
        let (model, transport) = try await connectedModel(extra: [challenge, .init(body: #"{"accessToken":"AT2","refreshToken":"RT2"}"#)])

        #expect(await model.changePassword(current: "pw", new: "NewPassw0rd!", confirm: "NewPassw0rd!") == nil)
        #expect(model.toast == "Password changed")
        #expect(transport.authPaths.last == "/api/account/password/change")
        #expect(model.connection != .standalone)

        let relaunch = await restarted()
        #expect(await relaunch.unlock(password: "NewPassw0rd!"))
        #expect(relaunch.entries.count == 2)
        let old = await restarted()
        #expect(await old.unlock(password: "pw") == false)
    }

    @Test func aWrongCurrentPasswordIsExplained() async throws {
        let challenge = try loginReplies(password: "pw", serverKey: KeyDerivation.generateVaultKey())[0]
        let (model, _) = try await connectedModel(extra: [challenge, .init(status: 401), .init(body: #"{"accessToken":"A","refreshToken":"R"}"#), .init(status: 401)])
        #expect(await model.changePassword(current: "nope", new: "NewPassw0rd!", confirm: "NewPassw0rd!") == "Current password is incorrect")
        #expect(model.toast == nil)
    }

    @Test func changePasswordChecksTheFormBeforeTheNetwork() async throws {
        let (model, transport) = try await connectedModel(extra: [])
        let before = transport.paths.count
        #expect(await model.changePassword(current: "pw", new: "NewPassw0rd!", confirm: "different") == "Passwords do not match")
        #expect(await model.changePassword(current: "pw", new: "short", confirm: "short") == "Password must be at least 8 characters")
        #expect(transport.paths.count == before)
    }

    @Test func changePasswordNeedsAConnection() async {
        let (model, transport) = await unlockedModel([])
        #expect(await model.changePassword(current: "pw", new: "NewPassw0rd!", confirm: "NewPassw0rd!") == "Not connected or vault locked")
        #expect(transport.paths.isEmpty)
    }

    @Test func anExpiredSessionDuringAPasswordChangeAsksToSignInAgain() async throws {
        let challenge = try loginReplies(password: "pw", serverKey: KeyDerivation.generateVaultKey())[0]
        let (model, _) = try await connectedModel(extra: [challenge, .init(status: 401), .init(status: 401)])
        let message = await model.changePassword(current: "pw", new: "NewPassw0rd!", confirm: "NewPassw0rd!")
        #expect(message == "Session expired — sign in again, then change the password")
        #expect(model.connection == .expired(serverUrl: "https://x.test/api", email: "a@b.c"))
    }

    // MARK: Devices

    private func deviceJSON(_ id: String, _ status: String, key: String? = nil) -> String {
        let keyField = key.map { "\"\($0)\"" } ?? "null"
        return """
        {"deviceId":"\(id)","deviceName":"Dev \(id)","platform":"ios","status":"\(status)","devicePublicKey":\(keyField),
         "approvalRequestId":null,"approvedAt":"2026-11-01T00:00:00Z","revokedAt":null}
        """
    }

    @Test func theDeviceListIsGroupedAndKnowsWhichOneIsThisDevice() async throws {
        let (model, transport) = try await connectedModel(extra: [])
        transport.devicesBody = "{\"devices\":[\(deviceJSON("d1", "approved")),\(deviceJSON("other", "pending")),\(deviceJSON("old", "revoked"))]}"
        guard case .success(let snapshot) = await model.loadDevices() else { Issue.record("load failed"); return }
        #expect(snapshot.currentDeviceId == "d1")        // the id the server gave this device at login
        #expect(snapshot.groups.pending.map(\.deviceId) == ["other"])
        #expect(snapshot.groups.approved.map(\.deviceId) == ["d1"])
        #expect(snapshot.groups.revoked.map(\.deviceId) == ["old"])
    }

    @Test func approvingHandsTheVaultKeyToThePendingDevice() async throws {
        let (model, transport) = try await connectedModel(extra: [])
        let theirKey = Ecdh.generateKeyPair()
        let pending = try JSONDecoder().decode(DeviceInfoDto.self, from: Data(
            deviceJSON("new", "pending", key: Ecdh.exportPublicKey(theirKey.publicKey).base64EncodedString()).utf8))

        #expect(await model.approveDevice(pending) == nil)
        #expect(transport.deviceRequests == ["POST /devices/new/approve"])
        // The envelope in the request opens with the new device's key, to the key this vault uses.
        let sentData = try #require(transport.lastDeviceBody)
        let body = try #require(try JSONSerialization.jsonObject(with: sentData) as? [String: Any])
        let env = try #require(body["deviceEnvelope"] as? [String: Any])
        let sent = Envelope(ciphertext: try #require(env["ciphertext"] as? String), nonce: try #require(env["nonce"] as? String))
        let unwrapped = try Ecdh.unpackDeviceEnvelope(sent, devicePrivateKey: theirKey)
        #expect(unwrapped.count == 32)
        #expect((body["approvalAuth"] as? [String: Any])?["type"] as? String == "device")
        #expect(body["approvalRequestId"] as? String == "new")
    }

    @Test func aDeviceWithoutAKeyCantBeApprovedAndNothingIsSent() async throws {
        let (model, transport) = try await connectedModel(extra: [])
        let pending = try JSONDecoder().decode(DeviceInfoDto.self, from: Data(deviceJSON("new", "pending").utf8))
        #expect(await model.approveDevice(pending) == "Approve failed: This device didn't provide a key, so it can't be approved.")
        #expect(transport.deviceRequests.isEmpty)
    }

    @Test func rejectAndRevokeCallTheServer() async throws {
        let (model, transport) = try await connectedModel(extra: [])
        let other = try JSONDecoder().decode(DeviceInfoDto.self, from: Data(deviceJSON("other", "approved").utf8))
        #expect(await model.rejectDevice(other) == nil)
        #expect(await model.revokeDevice(other) == nil)
        #expect(transport.deviceRequests == ["POST /devices/other/reject", "POST /devices/other/revoke"])
    }

    @Test func thisDeviceCantBeRevokedFromHere() async throws {
        let (model, transport) = try await connectedModel(extra: [])
        let mine = try JSONDecoder().decode(DeviceInfoDto.self, from: Data(deviceJSON("d1", "approved").utf8))
        #expect(await model.revokeDevice(mine) == "This is the device you're using. Use Disconnect in Settings instead.")
        #expect(transport.deviceRequests.isEmpty)
    }

    @Test func serverRefusalsAreShownAndAnExpiredSessionAsksToSignInAgain() async throws {
        let (model, transport) = try await connectedModel(extra: [])
        let other = try JSONDecoder().decode(DeviceInfoDto.self, from: Data(deviceJSON("other", "approved").utf8))
        transport.deviceActionStatus = 403
        #expect(await model.revokeDevice(other) == "Revoke failed: Access denied (HTTP 403)")
        #expect(model.connection != .standalone)

        transport.deviceActionStatus = 401   // refresh is then answered 500 by the exhausted script → session over
        _ = await model.revokeDevice(other)
        if case .expired = model.connection {} else { Issue.record("expected an expired session, got \(model.connection)") }
    }

    // MARK: Audit log

    @Test func theAuditLogIsLoadedNewestFirstAsTheServerSendsIt() async throws {
        let (model, transport) = try await connectedModel(extra: [])
        transport.auditBody = """
        {"events":[
          {"id":"e2","eventType":"DeviceApproved","eventData":"{\\"deviceName\\":\\"iPhone\\"}","ipAddress":"203.0.113.9","createdAt":"2026-11-19T10:30:00.1234567Z","deviceId":"d1"},
          {"id":"e1","eventType":"LoginSuccess","eventData":null,"ipAddress":null,"createdAt":"2026-11-19T09:00:00Z","deviceId":null}]}
        """
        guard case .success(let events) = await model.loadAuditEvents() else { Issue.record("load failed"); return }
        #expect(events.map(\.id) == ["e2", "e1"])
        #expect(events[0].ipAddress == "203.0.113.9" && events[1].ipAddress == nil)
        #expect(transport.auditPaths == ["https://x.test/api/security/audit-events?limit=100"])
    }

    @Test func anAuditLogFailureIsShown() async throws {
        let (model, transport) = try await connectedModel(extra: [])
        transport.auditStatus = 403
        guard case .failure(let failure) = await model.loadAuditEvents() else { Issue.record("expected a failure"); return }
        #expect(failure.message == "Access denied (HTTP 403)")
        #expect(model.connection != .standalone)
    }

    @Test func anExpiredSessionWhileLoadingTheAuditLogAsksToSignInAgain() async throws {
        let (model, transport) = try await connectedModel(extra: [])
        transport.auditStatus = 401   // the refresh is then refused by the exhausted script
        _ = await model.loadAuditEvents()
        if case .expired = model.connection {} else { Issue.record("expected an expired session, got \(model.connection)") }
    }

    // MARK: Recovery codes

    @Test func regeneratingRecoveryCodesReturnsEightNewOnes() async throws {
        let challenge = try loginReplies(password: "pw", serverKey: KeyDerivation.generateVaultKey())[0]
        let (model, transport) = try await connectedModel(extra: [challenge, .init()])
        guard case .success(let codes) = await model.regenerateRecoveryCodes(password: "pw") else { Issue.record("failed"); return }
        #expect(codes.count == RecoveryCodes.count)
        #expect(transport.authPaths.last == "/api/recovery/codes/regenerate")
    }

    @Test func aWrongPasswordIsRefusedBeforeAnythingIsSent() async throws {
        let (model, transport) = try await connectedModel(extra: [])
        let before = transport.paths.count
        guard case .failure(let failure) = await model.regenerateRecoveryCodes(password: "nope") else { Issue.record("expected a failure"); return }
        #expect(failure.message == "Incorrect password")
        #expect(transport.paths.count == before)
    }

    @Test func regeneratingNeedsAConnection() async {
        let (model, _) = await unlockedModel([])
        guard case .failure(let failure) = await model.regenerateRecoveryCodes(password: "pw") else { Issue.record("expected a failure"); return }
        #expect(failure.message == "Not connected")
    }

    @Test func anExpiredSessionWhileRegeneratingAsksToSignInAgain() async throws {
        let challenge = try loginReplies(password: "pw", serverKey: KeyDerivation.generateVaultKey())[0]
        let (model, _) = try await connectedModel(extra: [challenge, .init(status: 401), .init(status: 401)])
        _ = await model.regenerateRecoveryCodes(password: "pw")
        if case .expired = model.connection {} else { Issue.record("expected an expired session, got \(model.connection)") }
    }
}
