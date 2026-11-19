import Foundation
import GRDB
import Testing
@testable import PsTotpCore

@Suite("AuthService")
struct AuthServiceTests {
    let url = "https://x.test/api"
    let db: AppDatabase
    let repo: VaultRepository
    let secrets = InMemorySecretStore()
    let biometricCleared = LockedBox(0)

    let localKey0 = KeyDerivation.generateVaultKey()

    init() throws {
        db = try AppDatabase.inMemory()
        repo = VaultRepository(db: db)
    }

    private func make(_ replies: [StubTransport.Reply]) -> (AuthService, StubTransport, ApiClient) {
        let stub = StubTransport(replies)
        let client = ApiClient(baseURL: "", transport: stub)
        let cleared = biometricCleared
        let service = AuthService(repository: repo, client: client, secrets: secrets,
                                  invalidateBiometric: { cleared.set(cleared.get() + 1) })
        return (service, stub, client)
    }

    private func json(_ request: URLRequest) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
    }

    /// The device key the service persisted (the nested-#require form isn't allowed by Swift Testing).
    private func storedDeviceKey() throws -> Ecdh.PrivateKey {
        let b64 = try #require(try secrets.get(.ecdhPrivateKey))
        let der = try #require(Data(base64Encoded: b64))
        return try Ecdh.importPrivateKey(der)
    }

    private func envelopeJSON(_ e: Envelope) -> String {
        #"{"ciphertext":"\#(e.ciphertext)","nonce":"\#(e.nonce)","version":\#(e.version)}"#
    }

    // MARK: Login

    /// Challenge with a 32 MiB / t=2 / p=1 KDF (the allowed minimum) so tests stay fast.
    private let guid = "0f8fad5b-d9cb-469f-a165-70867728950e"
    private let salt = Data((1...16).map { UInt8($0) })
    private let nonce = Data((0..<16).map { UInt8(0x90 + $0) })

    private var challengeReply: StubTransport.Reply {
        .init(body: """
        {"loginSessionId":"\(guid)","challenge":{"nonce":"\(nonce.base64EncodedString())",
         "kdf":{"algorithm":"argon2id","memoryMb":32,"iterations":2,"parallelism":1,"salt":"\(salt.base64EncodedString())"}}}
        """)
    }

    private func authKey(_ password: String) throws -> Data {
        try Argon2.hash(password: password, salt: salt, memoryMb: 32, iterations: 2, parallelism: 1)
    }

    @Test func loginWithPasswordEnvelopeAdoptsTheServerVaultKey() async throws {
        let password = "correct horse"
        let serverKey = KeyDerivation.generateVaultKey()
        let ak = try authKey(password)
        let passwordEnvelope = try EnvelopeHelper.encrypt(key: KeyDerivation.deriveEnvelopeKey(authKey: ak), plaintext: serverKey)
        let (service, stub, client) = make([
            challengeReply,
            .init(body: """
            {"userId":"u1","accessToken":"AT","refreshToken":"RT","device":{"deviceId":"d1","status":"approved"},
             "envelopes":{"password":\(envelopeJSON(passwordEnvelope)),"device":null}}
            """),
            .init(),   // updateSelfEnvelope
        ])

        let result = try await service.login(serverUrl: url + "/", email: "a@b.c", password: password, localVaultKey: localKey0)
        #expect(result == .approved(serverVaultKey: serverKey))

        // The proof is exactly HMAC(verifier, nonce || guid) over the server's KDF.
        let expectedProof = try ClientProof.compute(verifier: KeyDerivation.deriveVerifier(authKey: ak), nonce: nonce, loginSessionId: guid)
        let completeBody = try json(stub.requests[1])
        #expect(completeBody["clientProof"] as? String == expectedProof.base64EncodedString())
        #expect(completeBody["loginSessionId"] as? String == guid)
        #expect(stub.requests[0].url?.absoluteString == "https://x.test/api/auth/login")
        let device = try #require(try json(stub.requests[0])["device"] as? [String: Any])
        #expect(device["clientType"] as? String == "ios")

        // Session, tokens and the local password envelope now belong to the server's vault key.
        #expect(try await repo.getSetting(SettingsKeys.mode) == SettingsKeys.modeConnected)
        #expect(try await repo.getSetting(SettingsKeys.serverUrl) == url + "/")
        #expect(try await repo.getSetting(SettingsKeys.email) == "a@b.c")
        #expect(try await repo.getSetting(SettingsKeys.userId) == "u1")
        #expect(try await repo.getSetting(SettingsKeys.deviceId) == "d1")
        #expect(try secrets.get(.accessToken) == "AT" && secrets.get(.refreshToken) == "RT")
        #expect(await client.hasTokens)
        #expect(try await service.isConnected())
        let stored = try #require(try await repo.getSetting(SettingsKeys.encryptedVaultKey))
        #expect(!stored.isEmpty)
        #expect(biometricCleared.get() == 1)

        // Offline unlock derives with the pinned parameters, not the server's (32 MiB here): the
        // same password must still open the local vault, with the server's key.
        #expect(try await repo.unlockVault(password: password) == serverKey)

        // The device envelope was refreshed for future device-key logins.
        #expect(stub.requests[2].url?.path == "/api/devices/self/envelope")
        #expect(stub.requests[2].httpMethod == "PUT")
    }

    @Test func anAccountWithTheDefaultParametersReusesTheDerivedKey() async throws {
        // 64 MiB / t=3 / p=4: the local envelope can use the key derived for the login proof.
        let password = "default params"
        let serverKey = KeyDerivation.generateVaultKey()
        let ak = try Argon2.hash(password: password, salt: salt)
        let envelope = try EnvelopeHelper.encrypt(key: KeyDerivation.deriveEnvelopeKey(authKey: ak), plaintext: serverKey)
        let (service, _, _) = make([
            .init(body: """
            {"loginSessionId":"\(guid)","challenge":{"nonce":"\(nonce.base64EncodedString())",
             "kdf":{"algorithm":"argon2id","memoryMb":64,"iterations":3,"parallelism":4,"salt":"\(salt.base64EncodedString())"}}}
            """),
            .init(body: """
            {"userId":"u","accessToken":"AT","refreshToken":"RT","device":{"deviceId":"d","status":"approved"},"envelopes":{"password":\(envelopeJSON(envelope))}}
            """), .init()])
        #expect(try await service.login(serverUrl: url, email: "a@b.c", password: password, localVaultKey: localKey0) == .approved(serverVaultKey: serverKey))
        #expect(try await repo.unlockVault(password: password) == serverKey)
    }

    @Test func kdfParametersAreRecognisedAsPinnedOrNot() {
        #expect(KdfConfig.default(saltBase64: "x").isPinnedDefault)
        #expect(!KdfConfig(algorithm: "argon2id", memoryMb: 128, iterations: 3, parallelism: 4, salt: "x").isPinnedDefault)
        #expect(!KdfConfig(algorithm: "argon2id", memoryMb: 64, iterations: 2, parallelism: 4, salt: "x").isPinnedDefault)
        #expect(!KdfConfig(algorithm: "argon2id", memoryMb: 64, iterations: 3, parallelism: 8, salt: "x").isPinnedDefault)
    }

    @Test func loginPrefersTheDeviceEnvelope() async throws {
        let serverKey = KeyDerivation.generateVaultKey()
        let (service, _, _) = make([challengeReply, .init(), .init()])
        // First login generates + stores the device key; build an envelope for it.
        _ = try? await service.login(serverUrl: url, email: "a@b.c", password: "pw", localVaultKey: localKey0)   // fails (empty reply), key persisted
        let key = try storedDeviceKey()
        let deviceEnvelope = try Ecdh.packDeviceEnvelope(vaultKey: serverKey, recipientPublicKey: key.publicKey)

        let (second, _, _) = make([
            challengeReply,
            .init(body: """
            {"userId":"u","accessToken":"AT","refreshToken":"RT","device":{"deviceId":"d","status":"approved"},
             "envelopes":{"password":{"ciphertext":"AAAA","nonce":"AAAA","version":1},"device":\(envelopeJSON(deviceEnvelope))}}
            """),
            .init(),
        ])
        #expect(try await second.login(serverUrl: url, email: "a@b.c", password: "pw", localVaultKey: localKey0) == .approved(serverVaultKey: serverKey))
    }

    @Test func pendingDeviceKeepsTokensButIsNotConnected() async throws {
        let (service, _, client) = make([
            challengeReply,
            .init(body: """
            {"userId":"u","accessToken":"AT","refreshToken":"RT","device":{"deviceId":"d9","status":"pending"},"approvalRequestId":"req1"}
            """),
        ])
        let result = try await service.login(serverUrl: url, email: "a@b.c", password: "pw", localVaultKey: localKey0)
        #expect(result == .pendingApproval(approvalRequestId: "req1"))
        #expect(try await repo.getSetting(SettingsKeys.mode) == nil)
        #expect(try await repo.getSetting(SettingsKeys.deviceId) == "d9")
        #expect(await client.hasTokens)
        #expect(biometricCleared.get() == 0)
    }

    @Test func wrongPasswordLeavesNothingDecryptable() async throws {
        let ak = try authKey("right")
        let envelope = try EnvelopeHelper.encrypt(key: KeyDerivation.deriveEnvelopeKey(authKey: ak), plaintext: KeyDerivation.generateVaultKey())
        let (service, _, _) = make([
            challengeReply,
            .init(body: """
            {"userId":"u","accessToken":"AT","refreshToken":"RT","device":{"deviceId":"d","status":"approved"},
             "envelopes":{"password":\(envelopeJSON(envelope))}}
            """),
        ])
        let result = try await service.login(serverUrl: url, email: "a@b.c", password: "wrong", localVaultKey: localKey0)
        #expect(result == .error("No envelope available to decrypt vault key"))
        #expect(try await repo.getSetting(SettingsKeys.mode) == nil)
        #expect(try await repo.getSetting(SettingsKeys.passwordVerifier) == nil)
    }

    @Test func serverKdfBelowTheFloorIsRejected() async throws {
        let (service, stub, _) = make([.init(body: """
        {"loginSessionId":"\(guid)","challenge":{"nonce":"AAAA","kdf":{"algorithm":"argon2id","memoryMb":8,"iterations":1,"parallelism":1,"salt":"AAAA"}}}
        """)])
        await #expect(throws: CryptoError.self) { _ = try await service.login(serverUrl: url, email: "a@b.c", password: "pw", localVaultKey: localKey0) }
        #expect(stub.requests.count == 1)   // never reached /login/complete
    }

    @Test func apiErrorsPropagate() async throws {
        let (service, _, _) = make([.init(status: 401, body: #"{"detail":"Invalid credentials"}"#)])
        await #expect(throws: ApiError.http(status: 401, message: "Invalid credentials")) {
            _ = try await service.login(serverUrl: url, email: "a@b.c", password: "pw", localVaultKey: localKey0)
        }
        #expect(try await service.isConnected() == false)
    }

    // MARK: Adopting the account's vault key

    private func addLocalEntries(_ count: Int) async throws {
        for n in 0..<count {
            try await repo.addEntry(vaultKey: localKey0,
                                    plaintext: VaultEntryPlaintext(issuer: "Svc\(n)", accountName: "u\(n)", secret: "JBSWY3DPEHPK3PXP"))
        }
    }

    @Test func connectingReencryptsLocalEntriesAndIconsWithTheServerKey() async throws {
        try await addLocalEntries(3)
        let library = IconLibraryRepository(db: db)
        try await library.save(vaultKey: localKey0, icons: [LibraryIcon(id: "i", label: "L", data: "data:image/png;base64,AAAA", createdAt: "t")])
        try await repo.setSetting(SettingsKeys.iconLibraryDirty, "false")

        let serverKey = KeyDerivation.generateVaultKey()
        let ak = try authKey("pw")
        let envelope = try EnvelopeHelper.encrypt(key: KeyDerivation.deriveEnvelopeKey(authKey: ak), plaintext: serverKey)
        let (service, _, _) = make([challengeReply, .init(body: """
            {"userId":"u","accessToken":"AT","refreshToken":"RT","device":{"deviceId":"d","status":"approved"},"envelopes":{"password":\(envelopeJSON(envelope))}}
            """), .init()])
        #expect(try await service.login(serverUrl: url, email: "a@b.c", password: "pw", localVaultKey: localKey0) == .approved(serverVaultKey: serverKey))

        let entries = try await repo.getAllEntries(vaultKey: serverKey)
        #expect(entries.map(\.issuer) == ["Svc0", "Svc1", "Svc2"])
        #expect(try await library.load(vaultKey: serverKey).map(\.id) == ["i"])
        #expect(try await library.load(vaultKey: localKey0).isEmpty)
        #expect(try await repo.getSetting(SettingsKeys.iconLibraryDirty) == "true")
        let pending = try await db.writer.read { try VaultEntryRecord.fetchAll($0).map(\.pendingSync) }
        #expect(pending == [true, true, true])
        #expect(biometricCleared.get() == 1)
    }

    @Test func aWrongLocalKeyChangesNothing() async throws {
        try await addLocalEntries(3)
        let before = try await db.writer.read { try VaultEntryRecord.fetchAll($0).map(\.encryptedPayload) }
        let serverKey = KeyDerivation.generateVaultKey()
        let ak = try authKey("pw")
        let envelope = try EnvelopeHelper.encrypt(key: KeyDerivation.deriveEnvelopeKey(authKey: ak), plaintext: serverKey)
        let (service, _, _) = make([challengeReply, .init(body: """
            {"userId":"u","accessToken":"AT","refreshToken":"RT","device":{"deviceId":"d","status":"approved"},"envelopes":{"password":\(envelopeJSON(envelope))}}
            """)])
        await #expect(throws: VaultKeyMismatchError.self) {
            _ = try await service.login(serverUrl: url, email: "a@b.c", password: "pw", localVaultKey: KeyDerivation.generateVaultKey())
        }
        // Rolled back: not connected, no new password envelope, entries untouched.
        #expect(try await repo.getSetting(SettingsKeys.mode) == nil)
        #expect(try await repo.getSetting(SettingsKeys.passwordVerifier) == nil)
        #expect(try await db.writer.read { try VaultEntryRecord.fetchAll($0).map(\.encryptedPayload) } == before)
        #expect(try await repo.getAllEntries(vaultKey: localKey0).count == 3)
        #expect(biometricCleared.get() == 0)
    }

    @Test func registeringReencryptsLocalEntriesToo() async throws {
        try await addLocalEntries(2)
        let (service, _, _) = make([.init(body: #"{"userId":"u1","deviceId":"d1","accessToken":"AT","refreshToken":"RT"}"#)])
        let result = try await service.register(serverUrl: url, email: "a@b.c", password: "pw", registrationSessionId: nil, localVaultKey: localKey0)
        #expect(try await repo.getAllEntries(vaultKey: result.vaultKey).count == 2)
    }

    @Test func sameKeyLeavesEntriesAlone() async throws {
        try await addLocalEntries(2)
        let ak = try authKey("pw")
        let envelope = try EnvelopeHelper.encrypt(key: KeyDerivation.deriveEnvelopeKey(authKey: ak), plaintext: localKey0)
        let (service, _, _) = make([challengeReply, .init(body: """
            {"userId":"u","accessToken":"AT","refreshToken":"RT","device":{"deviceId":"d","status":"approved"},"envelopes":{"password":\(envelopeJSON(envelope))}}
            """), .init()])
        _ = try await service.login(serverUrl: url, email: "a@b.c", password: "pw", localVaultKey: localKey0)
        #expect(try await db.writer.read { try VaultEntryRecord.fetchAll($0).map(\.pendingSync) } == [false, false])
        #expect(biometricCleared.get() == 0)   // the biometric copy is still the right key
    }

    // MARK: Registration

    @Test func registerBuildsConsistentCryptoMaterial() async throws {
        let password = "pässword 🔐"
        let (service, stub, client) = make([.init(body: #"{"userId":"u1","deviceId":"d1","accessToken":"AT","refreshToken":"RT"}"#)])
        let result = try await service.register(serverUrl: url, email: "a@b.c", password: password, registrationSessionId: "sess", localVaultKey: localKey0)

        let body = try json(stub.requests[0])
        #expect(stub.requests[0].url?.path == "/api/auth/register")
        #expect(body["registrationSessionId"] as? String == "sess" && body["email"] as? String == "a@b.c")
        let verifier = try #require(body["passwordVerifier"] as? [String: Any])
        let kdf = try #require(verifier["kdf"] as? [String: Any])
        #expect(kdf["memoryMb"] as? Int == 64 && kdf["iterations"] as? Int == 3 && kdf["parallelism"] as? Int == 4)
        let saltB64 = try #require(kdf["salt"] as? String)
        let salt = try #require(Data(base64Encoded: saltB64))
        let ak = try KeyDerivation.derivePasswordAuthKey(password: password, salt: salt)
        #expect(verifier["verifier"] as? String == KeyDerivation.deriveVerifier(authKey: ak).base64EncodedString())

        func envelope(_ any: Any?) throws -> Envelope {
            let o = try #require(any as? [String: Any])
            return Envelope(ciphertext: try #require(o["ciphertext"] as? String), nonce: try #require(o["nonce"] as? String))
        }
        // Password envelope → vault key.
        #expect(try EnvelopeHelper.decrypt(key: KeyDerivation.deriveEnvelopeKey(authKey: ak), envelope: try envelope(body["passwordEnvelope"])) == result.vaultKey)
        // Device envelope → vault key, using the persisted device key whose public half was registered.
        let storedKey = try storedDeviceKey()
        let device = try #require(body["device"] as? [String: Any])
        #expect(device["devicePublicKey"] as? String == Ecdh.exportPublicKey(storedKey.publicKey).base64EncodedString())
        #expect(try Ecdh.unpackDeviceEnvelope(try envelope(body["deviceEnvelope"]), devicePrivateKey: storedKey) == result.vaultKey)
        // Recovery material.
        let recovery = try #require(body["recovery"] as? [String: Any])
        let recEnv = Envelope(ciphertext: try #require(recovery["recoveryEnvelopeCiphertext"] as? String),
                              nonce: try #require(recovery["recoveryEnvelopeNonce"] as? String))
        #expect(try EnvelopeHelper.decrypt(key: KeyDerivation.deriveRecoveryUnlockKey(recoverySeed: ak), envelope: recEnv) == result.vaultKey)
        let hashes = try #require(recovery["recoveryCodeHashes"] as? [String])
        let codeSaltB64 = try #require(recovery["recoveryCodeSalt"] as? String)
        let codeSalt = try #require(Data(base64Encoded: codeSaltB64))
        #expect(hashes.count == RecoveryCodes.count && result.recoveryCodes.count == RecoveryCodes.count)
        #expect(hashes[0] == (try Argon2.hashRecoveryCode(result.recoveryCodes[0], salt: codeSalt)).base64EncodedString())
        #expect(hashes.last == (try Argon2.hashRecoveryCode(result.recoveryCodes.last!, salt: codeSalt)).base64EncodedString())

        // Local state: connected, tokens, and offline unlock with the same password gives the same key.
        #expect(try await repo.getSetting(SettingsKeys.mode) == SettingsKeys.modeConnected)
        #expect(try secrets.get(.accessToken) == "AT")
        #expect(await client.hasTokens)
        #expect(try await repo.unlockVault(password: password) == result.vaultKey)
    }

    @Test func registerFailureLeavesNoSession() async throws {
        let (service, _, _) = make([.init(status: 400, body: #"{"detail":"Email already registered"}"#)])
        await #expect(throws: ApiError.http(status: 400, message: "Email already registered")) {
            _ = try await service.register(serverUrl: url, email: "a@b.c", password: "pw", registrationSessionId: nil, localVaultKey: localKey0)
        }
        #expect(try await repo.getSetting(SettingsKeys.mode) == nil)
        #expect(try await repo.getSetting(SettingsKeys.passwordVerifier) == nil)
        #expect(try secrets.get(.accessToken) == nil)
    }

    @Test func recoveryCodesAreUniqueAndUseTheUnambiguousAlphabet() {
        let codes = RecoveryCodes.generate() + RecoveryCodes.generate()
        #expect(codes.count == 16 && Set(codes).count == 16)
        for code in codes {
            #expect(code.count == RecoveryCodes.length && code.allSatisfy(RecoveryCodes.alphabet.contains))
        }
        #expect(!RecoveryCodes.alphabet.contains("O") && !RecoveryCodes.alphabet.contains("0"))
    }

    @Test func registerBeginAndVerifyEmail() async throws {
        let (service, stub, client) = make([
            .init(body: #"{"registrationSessionId":"s1","emailVerificationRequired":true,"verificationCode":"123456"}"#),
            .init(body: #"{"verified":true}"#),
        ])
        let begin = try await service.registerBegin(serverUrl: "https://y.test/api//", email: "a@b.c")
        #expect(begin.registrationSessionId == "s1" && begin.verificationCode == "123456")
        #expect(await client.baseURL == "https://y.test/api")
        #expect(try await service.verifyEmail(registrationSessionId: "s1", code: "123456"))
        #expect(stub.requests[1].url?.path == "/api/auth/register/verify-email")
    }

    // MARK: Logout & restore

    @Test func logoutClearsTheSessionButKeepsTheDeviceKeyAndEmail() async throws {
        let (service, _, client) = make([.init(body: #"{"userId":"u1","deviceId":"d1","accessToken":"AT","refreshToken":"RT"}"#), .init()])
        _ = try await service.register(serverUrl: url, email: "a@b.c", password: "pw", registrationSessionId: nil, localVaultKey: localKey0)
        try await repo.setSetting(SettingsKeys.lastSyncAt, "t")
        try await service.logout()

        #expect(try await repo.getSetting(SettingsKeys.mode) == SettingsKeys.modeStandalone)
        for key in [SettingsKeys.serverUrl, SettingsKeys.deviceId, SettingsKeys.userId, SettingsKeys.lastSyncAt] {
            #expect(try await repo.getSetting(key) == nil, "\(key)")
        }
        #expect(try await repo.getSetting(SettingsKeys.email) == "a@b.c")
        #expect(try secrets.get(.accessToken) == nil && secrets.get(.refreshToken) == nil)
        #expect(try secrets.get(.ecdhPrivateKey) != nil)
        let hasTokens = await client.hasTokens
        #expect(!hasTokens)
        #expect(try await service.isConnected() == false)
    }

    @Test func logoutWorksOffline() async throws {
        let (service, _, _) = make([.init(body: #"{"userId":"u1","deviceId":"d1","accessToken":"AT","refreshToken":"RT"}"#),
                                    .init(error: URLError(.notConnectedToInternet))])
        _ = try await service.register(serverUrl: url, email: "a@b.c", password: "pw", registrationSessionId: nil, localVaultKey: localKey0)
        try await service.logout()
        #expect(try await service.isConnected() == false)
    }

    @Test func restoreSessionReloadsTokensAndPersistsRefreshes() async throws {
        try await repo.setSetting(SettingsKeys.serverUrl, url)
        try secrets.setAll([.accessToken: "AT", .refreshToken: "RT"])
        let (service, stub, client) = make([
            .init(status: 401),
            .init(body: #"{"accessToken":"AT2","refreshToken":"RT2"}"#),
            .init(body: #"{"entries":[],"serverTime":"t"}"#),
        ])
        try await service.restoreSession()
        let (base, token) = (await client.baseURL, await client.accessToken)
        #expect(base == url && token == "AT")
        _ = try await VaultApi(client: client).fetchVault()
        #expect(stub.requests.count == 3)
        #expect(try secrets.get(.accessToken) == "AT2" && secrets.get(.refreshToken) == "RT2")   // refresh persisted
    }

    @Test func restoreSessionIsANoOpWithoutASavedSession() async throws {
        let (service, _, client) = make([])
        try await service.restoreSession()
        let hasTokens = await client.hasTokens
        #expect(!hasTokens)
    }
}

@Suite("ServerURL")
struct ServerURLTests {
    @Test func normalizesWhatPeopleType() {
        #expect(ServerURL.normalize("https://totp.example.com/api") == "https://totp.example.com/api")
        #expect(ServerURL.normalize("  totp.example.com ") == "https://totp.example.com/api")
        #expect(ServerURL.normalize("https://totp.example.com/") == "https://totp.example.com/api")
        #expect(ServerURL.normalize("HTTPS://Totp.Example.com/api///") == "https://Totp.Example.com/api")
        #expect(ServerURL.normalize("https://example.com/pstotp/api/") == "https://example.com/pstotp/api")   // sub-path mount
        #expect(ServerURL.normalize("http://192.168.1.5:8080") == "http://192.168.1.5:8080/api")
    }

    @Test func rejectsWhatIsNotAnAddress() {
        for bad in ["", "   ", "ftp://x.test/api", "https://", "https://user:pw@x.test/api", "https://x.test/api?x=1", "://x"] {
            #expect(ServerURL.normalize(bad) == nil, "\(bad)")
        }
    }

    @Test func displayHost() {
        #expect(ServerURL.displayHost("https://totp.example.com:8443/api") == "totp.example.com")
    }
}
