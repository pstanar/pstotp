import Foundation
import Observation
import PsTotpCore
import SwiftUI

/// App-wide state for the standalone vault: setup / lock state, decrypted entries, list settings.
/// The counterpart of Android's `VaultViewModel` (standalone parts only).
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case loading, needsSetup, locked, unlocked }

    private(set) var phase: Phase = .loading
    private(set) var entries: [VaultEntry] = []
    private(set) var sortMode: SortMode = .manual
    private(set) var sortReversed = false
    private(set) var layoutMode: LayoutMode = .list
    private(set) var lockTimeout: LockTimeout = .fiveMinutes
    /// Preview the next code near the end of each period, and copy it in the last seconds.
    private(set) var showNextCode = false
    /// The device's enrolled biometry (nil: none), read at startup.
    private(set) var biometry: BiometryKind?
    /// The user turned biometric unlock on and the key is still stored.
    private(set) var biometricEnabled = false
    /// Offer the biometric prompt on the unlock screen.
    var canUnlockWithBiometrics: Bool { biometricEnabled && biometry != nil }

    /// Shown on the setup / unlock screens.
    var errorMessage: String?
    /// Transient confirmation ("Code copied").
    private(set) var toast: String?

    /// The icon library ("My icons"), decrypted while unlocked.
    private(set) var libraryIcons: [LibraryIcon] = []
    /// Import preview option: add the imported entries' icons to My icons.
    var addIconsToLibrary = true

    /// Whether this device is linked to a server account.
    enum Connection: Equatable {
        case standalone
        case connected(serverUrl: String, email: String)
        /// Linked to an account whose session the server no longer accepts: sign in again to resume.
        case expired(serverUrl: String, email: String)
    }

    enum SyncState: Equatable {
        case idle
        case syncing
        case failed(String)
    }

    private(set) var syncState: SyncState = .idle
    /// The server's clock at the last completed sync (ISO 8601), as stored.
    private(set) var lastSyncAt: String?

    private(set) var connection: Connection = .standalone

    private let repository: VaultRepository
    private let iconLibrary: IconLibraryRepository
    private let biometrics: BiometricKeyStore
    private let auth: AuthService
    private let sync: SyncService?
    private let iconSync: IconLibrarySyncService?
    private let devicesApi: DevicesApi?
    private let auditApi: AuditApi?
    private let webAuthnApi: WebAuthnApi?
    /// The in-memory library came from (or was reconciled with) the server this session, so editing it
    /// can't overwrite the account's real library with a stale local copy.
    private var libraryHydrated = false
    private var syncAgain = false
    private var syncTask: Task<Void, Never>?
    private var vaultKey: Data?
    private var usage: [String: EntryUsageRecord] = [:]
    /// Usage as of the last (re)sort. Copying a code records usage but must not re-sort the list
    /// mid-session, or the row would jump under the user's finger (same rule as Android).
    private var sortUsage: [String: EntryUsageRecord] = [:]
    private var backgroundedAt: Date?
    private var toastTask: Task<Void, Never>?
    private var writeQueue: Task<Void, Never>?

    /// Original bytes of the icons resolved for the import being previewed, by normalised data URL.
    private var importIconSources: [String: Data] = [:]

    /// - Parameter auth: Server authentication; defaults to one with no server reachable state and
    ///   in-memory secrets (tests that don't exercise connected mode).
    init(
        repository: VaultRepository, iconLibrary: IconLibraryRepository,
        biometrics: BiometricKeyStore = KeychainBiometricKeyStore(),
        server: ServerSession? = nil
    ) {
        self.repository = repository
        self.iconLibrary = iconLibrary
        self.biometrics = biometrics
        let server = server ?? Self.makeServerSession(
            db: nil, repository: repository, biometrics: biometrics, secrets: InMemorySecretStore(), transport: URLSessionTransport())
        self.auth = server.auth
        self.sync = server.sync
        self.iconSync = server.iconSync
        self.devicesApi = server.devices
        self.auditApi = server.audit
        self.webAuthnApi = server.webAuthn
    }

    /// Authentication and sync, sharing one API client (so they share one set of tokens).
    struct ServerSession {
        let auth: AuthService
        let sync: SyncService?
        let iconSync: IconLibrarySyncService?
        let devices: DevicesApi?
        let audit: AuditApi?
        let webAuthn: WebAuthnApi?
    }

    /// - Parameter db: Needed for sync; nil builds a session without it (tests of other features).
    ///
    /// Replacing the vault key (connecting) also removes the biometric copy of the old one.
    static func makeServerSession(
        db: AppDatabase?, repository: VaultRepository, biometrics: BiometricKeyStore, secrets: SecretStore,
        transport: HTTPTransport
    ) -> ServerSession {
        let client = ApiClient(baseURL: "", transport: transport)
        let auth = AuthService(repository: repository, client: client, secrets: secrets) {
            biometrics.removeKey()
            try? await repository.setSetting(SettingsKeys.biometricEnabled, "false")
        }
        return ServerSession(
            auth: auth,
            sync: db.map { SyncService(db: $0, client: client, repository: repository) },
            iconSync: db.map { IconLibrarySyncService(library: IconLibraryRepository(db: $0), client: client) },
            devices: DevicesApi(client: client),
            audit: AuditApi(client: client),
            webAuthn: WebAuthnApi(client: client))
    }

    // MARK: Startup

    func start() async {
        guard phase == .loading else { return }
        do {
            let setUp = try await repository.isSetUp()
            sortMode = SortMode.fromStorageKey(try await repository.getSetting(SettingsKeys.sortMode))
            sortReversed = try await repository.getSetting(SettingsKeys.sortReversed) == "true"
            layoutMode = LayoutMode.fromStorageKey(try await repository.getSetting(SettingsKeys.layoutMode))
            showNextCode = try await repository.getSetting(SettingsKeys.showNextCode) == "true"
            lockTimeout = LockTimeout.fromMillis(
                try await repository.getSetting(SettingsKeys.lockTimeoutMs).flatMap { Int64($0) })
            try await loadUsage()
            sortUsage = usage
            biometry = biometrics.availableBiometry()
            if setUp {
                biometricEnabled = try await repository.getSetting(SettingsKeys.biometricEnabled) == "true"
                    && biometrics.hasStoredKey()
            } else {
                // Keychain items outlive an uninstall; keys and tokens left by an earlier install belong
                // to a vault that no longer exists.
                biometrics.removeKey()
                try? auth.removeAllSecrets()
            }
            try await restoreConnection()
            phase = setUp ? .locked : .needsSetup
        } catch {
            errorMessage = "Could not open the vault: \(error.localizedDescription)"
            phase = .needsSetup
        }
    }

    // MARK: Setup & unlock

    /// - Returns: true when the vault was created and is now unlocked.
    func setupPassword(_ password: String, confirm: String) async -> Bool {
        if let problem = PasswordPolicy.validate(password, confirm: confirm) {
            errorMessage = problem
            return false
        }
        do {
            let key = try await repository.setupPassword(password)
            vaultKey = key
            entries = []
            libraryIcons = []
            errorMessage = nil
            phase = .unlocked
            return true
        } catch {
            errorMessage = "Setup failed: \(error.localizedDescription)"
            return false
        }
    }

    /// - Returns: true when unlocked. Sets `errorMessage` otherwise.
    func unlock(password: String) async -> Bool {
        do {
            guard let key = try await repository.unlockVault(password: password) else {
                errorMessage = "Incorrect password"
                return false
            }
            return await finishUnlock(key: key)
        } catch {
            errorMessage = "Unlock failed: \(error.localizedDescription)"
            return false
        }
    }

    /// Unlock with the biometric copy of the vault key. A dismissed prompt is not an error.
    /// - Returns: true when unlocked.
    func unlockWithBiometrics() async -> Bool {
        guard canUnlockWithBiometrics else { return false }
        do {
            guard let key = try await biometrics.loadVaultKey(reason: "Unlock PsTotp") else {
                // The enrolled faces / fingers changed, so the key is gone for good.
                await turnOffBiometrics()
                errorMessage = "Biometric unlock was turned off because the enrolled \(biometry?.name ?? "biometrics") changed. Unlock with your password."
                return false
            }
            return await finishUnlock(key: key)
        } catch BiometricError.cancelled {
            return false
        } catch {
            errorMessage = "Biometric unlock failed: \(Self.message(error))"
            return false
        }
    }

    private func finishUnlock(key: Data) async -> Bool {
        do {
            // Decrypt before touching any state: a wrong-key failure must not leave the UI
            // "unlocked" with no entries.
            let decrypted = try await repository.getAllEntries(vaultKey: key)
            let library = (try? await iconLibrary.load(vaultKey: key)) ?? []
            vaultKey = key
            entries = decrypted
            libraryIcons = library
            libraryHydrated = false
            sortUsage = usage
            errorMessage = nil
            phase = .unlocked
            requestSync()
            return true
        } catch let mismatch as VaultKeyMismatchError {
            errorMessage = "Vault key mismatch: \(mismatch.failed) of \(mismatch.total) entries could not be decrypted."
            return false
        } catch {
            errorMessage = "Unlock failed: \(error.localizedDescription)"
            return false
        }
    }

    func lock() {
        // Zero the stored buffer in place. (Zeroing a `var` copy would only zero a copy-on-write
        // duplicate.) Best effort: a copy held by an in-flight repository call survives.
        if let count = vaultKey?.count { vaultKey?.resetBytes(in: 0..<count) }
        vaultKey = nil
        entries = []
        libraryIcons = []
        libraryHydrated = false
        importIconSources = [:]
        errorMessage = nil
        if phase == .unlocked { phase = .locked }
    }

    // MARK: Server connection

    enum ConnectOutcome: Equatable {
        case connected
        /// Signed in, but another approved device must approve this one first.
        case pendingApproval
        case failed(String)
    }

    enum RegistrationStart: Equatable {
        /// `code` is only present on servers that show it instead of emailing it (development).
        case started(sessionId: String, needsEmailCode: Bool, code: String?)
        case failed(String)
    }

    private func restoreConnection() async throws {
        try? await auth.restoreSession()
        if try await auth.isConnected(), let url = try await auth.serverUrl() {
            connection = .connected(serverUrl: url, email: try await repository.getSetting(SettingsKeys.email) ?? "")
            lastSyncAt = try await repository.getSetting(SettingsKeys.lastSyncAt)
        } else {
            connection = .standalone
        }
    }

    /// Sign in to an existing account. The account's vault key replaces the local one and local
    /// entries are re-encrypted with it, so the vault must be unlocked.
    func connect(serverUrl: String, email: String, password: String) async -> ConnectOutcome {
        guard let key = vaultKey else { return .failed("Vault is locked") }
        guard let url = ServerURL.normalize(serverUrl) else { return .failed("Enter a valid server address") }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch try await auth.login(serverUrl: url, email: email, password: password, localVaultKey: key) {
            case .approved(let serverKey):
                guard await adoptKey(serverKey) else { return .failed(errorMessage ?? "Connection failed") }
                connection = .connected(serverUrl: url, email: email)
                requestSync()
                return .connected
            case .pendingApproval:
                return .pendingApproval
            case .error(let message):
                return .failed(message)
            }
        } catch {
            return .failed(Self.connectionMessage(error))
        }
    }

    func beginRegistration(serverUrl: String, email: String) async -> RegistrationStart {
        guard let url = ServerURL.normalize(serverUrl) else { return .failed("Enter a valid server address") }
        do {
            let reply = try await auth.registerBegin(serverUrl: url, email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            return .started(sessionId: reply.registrationSessionId, needsEmailCode: reply.emailVerificationRequired,
                            code: reply.verificationCode)
        } catch {
            return .failed(Self.connectionMessage(error))
        }
    }

    /// - Returns: nil when verified, otherwise a message for the user.
    func verifyEmail(sessionId: String, code: String) async -> String? {
        do {
            return try await auth.verifyEmail(registrationSessionId: sessionId,
                                              code: code.trimmingCharacters(in: .whitespacesAndNewlines))
                ? nil : "Invalid verification code"
        } catch {
            return Self.connectionMessage(error)
        }
    }

    /// Create the account on the server. The new vault key is adopted at once (entries re-encrypted),
    /// so edits made while the recovery codes are on screen use the right key.
    /// - Returns: the recovery codes to show the user, or a message.
    func register(serverUrl: String, email: String, password: String, sessionId: String?) async -> Result<[String], ConnectionFailure> {
        guard let key = vaultKey else { return .failure(.init(message: "Vault is locked")) }
        guard let url = ServerURL.normalize(serverUrl) else { return .failure(.init(message: "Enter a valid server address")) }
        // Android's register screen only asks for 8 characters (the strong rules are for the local setup).
        if password.count < 8 { return .failure(.init(message: "Password must be at least 8 characters")) }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let result = try await auth.register(serverUrl: url, email: email, password: password,
                                                 registrationSessionId: sessionId, localVaultKey: key)
            guard await adoptKey(result.vaultKey) else { return .failure(.init(message: errorMessage ?? "Registration failed")) }
            connection = .connected(serverUrl: url, email: email)
            requestSync()
            return .success(result.recoveryCodes)
        } catch {
            return .failure(.init(message: Self.connectionMessage(error)))
        }
    }

    struct ConnectionFailure: Error, Equatable { let message: String }

    /// Change the account password (and this device's copy of it). The vault key is unchanged.
    /// - Returns: nil on success, otherwise a message for the user.
    func changePassword(current: String, new: String, confirm: String) async -> String? {
        // Android's rules for this screen: matching, and at least 8 characters.
        if new != confirm { return "Passwords do not match" }
        if new.count < 8 { return "Password must be at least 8 characters" }
        guard case .connected(let url, let email) = connection, !email.isEmpty, let key = vaultKey else {
            return "Not connected or vault locked"
        }
        do {
            switch try await auth.changePassword(email: email, currentPassword: current, newPassword: new, vaultKey: key) {
            case .success:
                showToast("Password changed")
                return nil
            case .incorrectCurrentPassword:
                return "Current password is incorrect"
            }
        } catch ApiError.sessionExpired {
            connection = .expired(serverUrl: url, email: email)
            return "Session expired — sign in again, then change the password"
        } catch {
            return Self.connectionMessage(error)
        }
    }

    // MARK: Devices

    struct DevicesSnapshot: Equatable {
        var groups: DeviceGroups
        /// This device's id on the server, to mark it and keep it from being revoked from here.
        var currentDeviceId: String?
    }

    func loadDevices() async -> Result<DevicesSnapshot, ConnectionFailure> {
        guard let devicesApi else { return .failure(.init(message: "Not connected")) }
        do {
            let list = try await devicesApi.fetchDevices().devices
            let current = try await repository.getSetting(SettingsKeys.deviceId)
            return .success(DevicesSnapshot(groups: DeviceListing.group(list), currentDeviceId: current))
        } catch {
            return .failure(.init(message: deviceFailure(error)))
        }
    }

    /// Let a pending device in by handing it the vault key, wrapped for its public key.
    /// - Returns: nil on success, otherwise a message for the user.
    func approveDevice(_ device: DeviceInfoDto) async -> String? {
        guard let devicesApi else { return "Not connected" }
        guard let key = vaultKey else { return "Vault is locked" }
        do {
            let envelope = try DeviceApproval.envelope(for: device, vaultKey: key)
            try await devicesApi.approveDevice(
                deviceId: device.deviceId, approvalRequestId: DeviceApproval.approvalRequestId(for: device),
                deviceEnvelope: envelope)
            return nil
        } catch {
            return "Approve failed: \(deviceFailure(error))"
        }
    }

    func rejectDevice(_ device: DeviceInfoDto) async -> String? {
        guard let devicesApi else { return "Not connected" }
        do {
            try await devicesApi.rejectDevice(deviceId: device.deviceId)
            return nil
        } catch {
            return "Reject failed: \(deviceFailure(error))"
        }
    }

    /// Sign an approved device out for good: its tokens and device envelope are revoked on the server.
    func revokeDevice(_ device: DeviceInfoDto) async -> String? {
        guard let devicesApi else { return "Not connected" }
        if (try? await repository.getSetting(SettingsKeys.deviceId)) == device.deviceId {
            return "This is the device you're using. Use Disconnect in Settings instead."
        }
        do {
            try await devicesApi.revokeDevice(deviceId: device.deviceId)
            return nil
        } catch {
            return "Revoke failed: \(deviceFailure(error))"
        }
    }

    // MARK: Account recovery

    /// Where a recovery stands after asking the server.
    enum RecoveryProgress: Equatable {
        /// Still inside the hold period; check again after `releaseEarliestAt`.
        case waiting(PendingRecovery)
        /// The session needs a passkey step-up, which the app can't do yet.
        case needsPasskey(PendingRecovery)
        case ready(PendingRecovery, envelope: Envelope, replacementDeviceId: String)
        case failed(String)
    }

    func pendingRecovery() async -> PendingRecovery? { try? await auth.pendingRecovery() }

    func forgetRecovery() async { try? await auth.forgetPendingRecovery() }

    /// Redeem a recovery code. The password is proven here and needed again to finish.
    func startRecovery(serverUrl: String, email: String, password: String, code: String) async -> Result<PendingRecovery, ConnectionFailure> {
        guard let url = ServerURL.normalize(serverUrl) else { return .failure(.init(message: "Enter a valid server address")) }
        do {
            return .success(try await auth.startRecovery(
                serverUrl: url, email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password, recoveryCode: code.trimmingCharacters(in: .whitespacesAndNewlines)))
        } catch {
            return .failure(.init(message: Self.connectionMessage(error)))
        }
    }

    func checkRecovery(_ pending: PendingRecovery) async -> RecoveryProgress {
        do {
            switch try await auth.recoveryMaterial(for: pending) {
            case .passkeyRequired: return .needsPasskey(pending)
            case .pending(let release):
                var updated = pending
                updated.releaseEarliestAt = release
                return .waiting(updated)
            case .ready(let envelope, let deviceId): return .ready(pending, envelope: envelope, replacementDeviceId: deviceId)
            }
        } catch {
            return .failed(Self.connectionMessage(error))
        }
    }

    /// Finish recovery: the account's vault key replaces the local one and this device is signed in.
    /// - Returns: the new recovery codes to show, or a message.
    func completeRecovery(
        _ pending: PendingRecovery, password: String, envelope: Envelope, replacementDeviceId: String
    ) async -> Result<[String], ConnectionFailure> {
        guard let key = vaultKey else { return .failure(.init(message: "Vault is locked")) }
        do {
            let result = try await auth.completeRecovery(
                pending: pending, password: password, envelope: envelope,
                replacementDeviceId: replacementDeviceId, localVaultKey: key)
            guard await adoptKey(result.vaultKey) else { return .failure(.init(message: errorMessage ?? "Recovery failed")) }
            if result.signedIn {
                connection = .connected(serverUrl: pending.serverUrl, email: pending.email)
                requestSync()
            }
            return .success(result.recoveryCodes)
        } catch {
            return .failure(.init(message: Self.connectionMessage(error)))
        }
    }

    // MARK: Passkeys

    /// The account's registered passkeys. (Adding one and signing in with one need the platform's
    /// passkey ceremony, which isn't ported yet.)
    func loadPasskeys() async -> Result<[WebAuthnCredentialInfo], ConnectionFailure> {
        guard let webAuthnApi else { return .failure(.init(message: "Not connected")) }
        do {
            return .success(try await webAuthnApi.listCredentials())
        } catch {
            return .failure(.init(message: deviceFailure(error)))
        }
    }

    /// - Returns: nil on success, otherwise a message for the user.
    func renamePasskey(id: String, to name: String) async -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Enter a name" }
        guard let webAuthnApi else { return "Not connected" }
        do {
            try await webAuthnApi.renameCredential(credentialId: id, friendlyName: name)
            return nil
        } catch {
            return "Rename failed: \(deviceFailure(error))"
        }
    }

    func revokePasskey(id: String) async -> String? {
        guard let webAuthnApi else { return "Not connected" }
        do {
            try await webAuthnApi.revokeCredential(credentialId: id)
            return nil
        } catch {
            return "Revoke failed: \(deviceFailure(error))"
        }
    }

    // MARK: Recovery codes

    /// Replace the account's recovery codes (the old ones stop working).
    /// - Returns: the new codes, or a message for the user.
    func regenerateRecoveryCodes(password: String) async -> Result<[String], ConnectionFailure> {
        guard case .connected(_, let email) = connection, !email.isEmpty else {
            return .failure(.init(message: "Not connected"))
        }
        guard let key = vaultKey else { return .failure(.init(message: "Vault is locked")) }
        do {
            switch try await auth.regenerateRecoveryCodes(email: email, password: password, vaultKey: key) {
            case .codes(let codes): return .success(codes)
            case .incorrectPassword: return .failure(.init(message: "Incorrect password"))
            }
        } catch {
            return .failure(.init(message: deviceFailure(error)))
        }
    }

    // MARK: Audit log

    /// The account's latest security events, newest first (the server orders them).
    func loadAuditEvents(limit: Int = 100) async -> Result<[AuditEventDto], ConnectionFailure> {
        guard let auditApi else { return .failure(.init(message: "Not connected")) }
        do {
            return .success(try await auditApi.fetchEvents(limit: limit).events)
        } catch {
            return .failure(.init(message: deviceFailure(error)))
        }
    }

    /// A message for a failed server call; an expired session also moves the app to "sign in again".
    private func deviceFailure(_ error: Error) -> String {
        if case ApiError.sessionExpired = error, case .connected(let url, let email) = connection {
            connection = .expired(serverUrl: url, email: email)
        }
        return Self.connectionMessage(error)
    }

    func disconnect() async {
        try? await auth.logout()
        connection = .standalone
        syncState = .idle
        lastSyncAt = nil
    }

    // MARK: Sync

    /// Sync in the background, e.g. after a change. Does nothing when not connected.
    func requestSync() {
        guard case .connected = connection, sync != nil else { return }
        if syncState == .syncing {
            syncAgain = true   // pick up what changed while a sync was already running
            return
        }
        syncTask = Task { await syncNow() }
    }

    /// Waits for a sync started by `requestSync()` (tests).
    func waitForPendingSync() async { await syncTask?.value }

    /// Push local changes, pull the server's, and refresh the list.
    func syncNow() async {
        guard case .connected(let url, let email) = connection, let sync, syncState != .syncing else { return }
        syncState = .syncing
        repeat {
            syncAgain = false
            switch await sync.fullSync() {
            case .success(let pulled, _):
                syncState = .idle
                lastSyncAt = try? await repository.getSetting(SettingsKeys.lastSyncAt)
                if pulled > 0 { await reloadEntries() }
                if let message = await syncLibrary() { syncState = .failed(message) }
            case .error(let message):
                syncState = .failed(message)
            case .sessionExpired:
                syncState = .idle
                connection = .expired(serverUrl: url, email: email)
                syncAgain = false
            case .notConnected:
                syncState = .idle
            }
        } while syncAgain
    }

    /// Reconcile My icons with the server (needs the unlocked vault: the library is encrypted).
    /// - Returns: a message when it failed, nil otherwise (including when locked).
    private func syncLibrary() async -> String? {
        guard let key = vaultKey, let iconSync else { return nil }
        do {
            libraryIcons = try await iconSync.sync(vaultKey: key)
            libraryHydrated = true
            return nil
        } catch {
            return "Couldn't sync My icons: \(Self.connectionMessage(error))"
        }
    }

    /// Connected library edits need the server's copy first (fail closed): a stale or empty local
    /// base must never replace the account's real library.
    private func libraryIsAuthoritative() async -> Bool {
        switch connection {
        case .standalone: return true
        case .connected, .expired:
            if libraryHydrated { return true }
            return await syncLibrary() == nil
        }
    }

    private static let libraryNotSynced = "Couldn't sync icon library — check your connection and try again."

    /// Re-read the entries after a pull. A decrypt failure here means the server holds entries
    /// encrypted with another key — shown, not hidden.
    private func reloadEntries() async {
        guard let key = vaultKey else { return }   // locked: the next unlock reads them
        do {
            entries = try await repository.getAllEntries(vaultKey: key)
            sortUsage = usage
        } catch {
            syncState = .failed("Synced entries can't be read: \(error.localizedDescription)")
        }
    }

    /// Switch the in-memory state to the account's vault key. Decrypts first, so a failure leaves the
    /// session as it was; on failure the half-made server session is dropped (as Android does).
    private func adoptKey(_ key: Data) async -> Bool {
        do {
            let decrypted = try await repository.getAllEntries(vaultKey: key)
            let library = (try? await iconLibrary.load(vaultKey: key)) ?? []
            vaultKey = key
            entries = decrypted
            libraryIcons = library
            libraryHydrated = false
            sortUsage = usage
            biometricEnabled = biometricEnabled && biometrics.hasStoredKey()
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Vault unlock failed: \(error.localizedDescription)"
            try? await auth.logout()
            return false
        }
    }

    private static func connectionMessage(_ error: Error) -> String {
        switch error {
        case let error as ApiError: return error.message
        case CryptoError.kdfParameterBelowMinimum(let detail): return "The server's key-derivation settings are too weak: \(detail)"
        case let mismatch as VaultKeyMismatchError: return "Couldn't re-encrypt your local accounts: \(mismatch)"
        default: return error.localizedDescription
        }
    }

    // MARK: Entries

    /// Validate and store a new entry.
    /// - Returns: nil on success, otherwise a message for the user.
    func addEntry(_ plaintext: VaultEntryPlaintext) async -> String? {
        guard let key = vaultKey else { return "Vault is locked" }
        do {
            let valid = try EntryValidation.validated(plaintext)
            let entry = try await repository.addEntry(vaultKey: key, plaintext: valid)
            entries.append(entry)
            sortUsage = usage
            requestSync()
            return nil
        } catch let error as EntryValidationError {
            return error.description
        } catch {
            return "Failed to add entry: \(error.localizedDescription)"
        }
    }

    /// Edit an entry's service name, account and icon (nil clears it). Secret, algorithm and order
    /// are untouched. An edit that changes nothing is not written, so it doesn't queue a pointless sync.
    /// - Returns: nil on success, otherwise a message for the user.
    func updateEntry(_ entry: VaultEntry, issuer: String, accountName: String, icon: String?) async -> String? {
        guard let key = vaultKey else { return "Vault is locked" }
        let edited = EntryValidation.edited(entry, issuer: issuer, accountName: accountName, icon: icon)
        guard edited != entry else { return nil }
        do {
            try await repository.updateEntry(vaultKey: key, entry: edited)
            if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = edited }
            requestSync()
            return nil
        } catch {
            return "Failed to update entry: \(error.localizedDescription)"
        }
    }

    func entry(id: String) -> VaultEntry? { entries.first { $0.id == id } }

    /// Apply a drag in the list. `shownIds` is the list as displayed (possibly search-filtered);
    /// hidden entries keep their slots. Only meaningful in manual sort — the user's own order.
    /// The list updates at once; the database write is queued and the list is reloaded if it fails.
    func moveEntries(shownIds: [String], fromOffsets: IndexSet, toOffset: Int) {
        guard sortMode == .manual else { return }
        let newVisible = EntryListing.moved(shownIds, fromOffsets: fromOffsets, toOffset: toOffset)
        let order = EntryListing.reordered(all: entries.map(\.id), visibleNewOrder: newVisible)
        guard order != entries.map(\.id) else { return }

        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        entries.sort { position[$0.id, default: .max] < position[$1.id, default: .max] }
        for index in entries.indices { entries[index].sortOrder = index }

        enqueue { [self] in
            do {
                try await repository.reorderEntries(orderedIds: order)
                requestSync()
            } catch {
                // The database didn't take the new order: show what is actually stored.
                if let key = vaultKey, let reloaded = try? await repository.getAllEntries(vaultKey: key) {
                    entries = reloaded
                }
            }
        }
    }

    func deleteEntry(id: String) async {
        do {
            try await repository.deleteEntry(id: id)
            entries.removeAll { $0.id == id }
            usage[id] = nil
            sortUsage[id] = nil
            requestSync()
        } catch {
            showToast("Failed to delete: \(error.localizedDescription)")
        }
    }

    func recordUse(of entry: VaultEntry) async {
        do {
            try await repository.recordEntryUse(entryId: entry.id)
            try await loadUsage()
        } catch {
            // Usage stats are best-effort; never interrupt the user over them.
        }
    }

    private func loadUsage() async throws {
        usage = Dictionary(uniqueKeysWithValues: try await repository.getAllUsage().map { ($0.entryId, $0) })
    }

    /// Entries in display order for the current sort settings, optionally filtered.
    func displayEntries(query: String = "") -> [VaultEntry] {
        EntryListing.filtered(
            EntryListing.sorted(entries, mode: sortMode, reversed: sortReversed, usage: sortUsage),
            query: query)
    }

    // MARK: Settings

    func setSortMode(_ mode: SortMode) {
        sortMode = mode
        sortUsage = usage
        persist(SettingsKeys.sortMode, mode.rawValue)
    }

    func setSortReversed(_ reversed: Bool) {
        sortReversed = reversed
        sortUsage = usage
        persist(SettingsKeys.sortReversed, String(reversed))
    }

    func setLayoutMode(_ mode: LayoutMode) {
        layoutMode = mode
        persist(SettingsKeys.layoutMode, mode.rawValue)
    }

    func setShowNextCode(_ show: Bool) {
        showNextCode = show
        persist(SettingsKeys.showNextCode, String(show))
    }

    func setLockTimeout(_ timeout: LockTimeout) {
        lockTimeout = timeout
        persist(SettingsKeys.lockTimeoutMs, String(timeout.millis))
    }

    // MARK: Biometric unlock

    /// Turn biometric unlock on (prompts, as on Android) or off.
    /// - Returns: nil on success or a dismissed prompt, otherwise a message for the user.
    func setBiometricEnabled(_ enabled: Bool) async -> String? {
        guard enabled else {
            await turnOffBiometrics()
            return nil
        }
        guard let key = vaultKey else { return "Vault is locked" }
        do {
            try await biometrics.enroll(vaultKey: key, reason: "Turn on biometric unlock")
            try await repository.setSetting(SettingsKeys.biometricEnabled, "true")
            biometricEnabled = true
            return nil
        } catch BiometricError.cancelled {
            return nil
        } catch {
            biometrics.removeKey()
            return "Failed to enable biometric unlock: \(Self.message(error))"
        }
    }

    private func turnOffBiometrics() async {
        biometrics.removeKey()
        biometricEnabled = false
        try? await repository.setSetting(SettingsKeys.biometricEnabled, "false")
    }

    private static func message(_ error: Error) -> String {
        if case BiometricError.failed(let message) = error { return message }
        return error.localizedDescription
    }

    // MARK: Import & export

    enum ImportPreparation {
        /// Ready for the user to confirm, duplicates flagged.
        case ready([ImportCandidate])
        /// An encrypted PsTotp export: ask for its password and call `prepareImport` again.
        case needsPassword
        case failed(String)
    }

    /// (done, total) while imported icons are being downloaded / normalised; nil otherwise.
    private(set) var importIconProgress: (done: Int, total: Int)?

    enum ExportOutcome {
        case file(String)
        case failed(String)
    }

    /// The vault's contents in `format`, or a message for the user.
    func exportVault(format: ExportFormat, password: String) async -> ExportOutcome {
        if format.needsPassword && password.isEmpty { return .failed("Password required") }
        let entries = entries
        do {
            // Encrypted export runs Argon2: keep it off the main actor.
            return .file(try await Task.detached(priority: .userInitiated) {
                try format.export(entries: entries, password: password)
            }.value)
        } catch {
            return .failed("Export failed: \(error.localizedDescription)")
        }
    }

    /// Parse an import file (decrypting it when `password` is given), resolve its icons and match
    /// it against the vault, as Android's `prepareImport` does.
    func prepareImport(_ content: String, password: String? = nil) async -> ImportPreparation {
        let parsed: [VaultEntryPlaintext]
        if let password {
            do {
                parsed = try await Task.detached(priority: .userInitiated) {
                    try VaultExport.importEncrypted(content, password: password)
                }.value
            } catch VaultExport.ExportError.wrongPasswordOrCorrupt {
                return .failed("Wrong password, or the file is damaged")
            } catch {
                return .failed("Import failed: \(error)")
            }
        } else {
            switch VaultExport.importAutoDetect(content) {
            case .success(let entries): parsed = entries
            case .needsPassword: return .needsPassword
            case .error(let message): return .failed(message)
            }
        }

        let iconCount = ImportIcons.pendingCount(parsed)
        if iconCount > 0 { importIconProgress = (0, iconCount) }
        let resolved = await ImportIcons.resolve(parsed, fetch: Self.fetchIcon) { done, total in
            await MainActor.run { self.importIconProgress = (done, total) }
        }
        importIconProgress = nil
        importIconSources = resolved.sourceBytes
        return .ready(ImportCandidate.buildCandidates(imported: resolved.entries, existing: entries))
    }

    /// Write the confirmed import in one transaction and reload the vault.
    /// - Returns: nil on success, otherwise a message for the user.
    func confirmImport(_ candidates: [ImportCandidate]) async -> String? {
        guard let key = vaultKey else { return "Vault is locked" }
        let plan = ImportCandidate.plan(candidates, existing: entries)
        do {
            try await repository.importEntries(vaultKey: key, plan: plan)
            entries = try await repository.getAllEntries(vaultKey: key)
            sortUsage = usage
            requestSync()
            let icons = await addImportedIconsToLibrary(candidates, key: key)
            showToast(ImportIcons.importMessage(entries: plan.count, icons: icons))   // Android's wording
            return nil
        } catch {
            return "Import failed: \(error.localizedDescription)"
        }
    }

    /// Opt-in, one batched write. Not fatal: the entries are already imported.
    private func addImportedIconsToLibrary(_ candidates: [ImportCandidate], key: Data) async -> IconBatchResult? {
        guard addIconsToLibrary else { return nil }
        let items = ImportIcons.libraryItems(candidates, sourceBytes: importIconSources)
        guard !items.isEmpty, await libraryIsAuthoritative(),
              let (icons, result) = try? await iconLibrary.addBatch(vaultKey: key, current: libraryIcons, items: items)
        else { return nil }
        libraryIcons = icons
        requestSync()
        return result
    }

    // MARK: Icon library

    /// Download an icon for the picker (5 s timeouts). Nil when it can't be fetched or decoded.
    func downloadIcon(from url: URL) async -> (dataUrl: String, source: Data)? {
        guard let bytes = await Self.fetchIcon(url),
              let dataUrl = IconNormalizer.normalizedDataUrl(imageBytes: bytes) else { return nil }
        return (dataUrl, bytes)
    }

    /// Save an icon to My icons, de-duplicated on content. Failures (library full) come back as a
    /// message; a duplicate is not a failure, the existing icon is simply kept.
    func addLibraryIcon(label: String, dataUrl: String, source: Data?) async -> String? {
        guard let key = vaultKey else { return "Vault is locked" }
        guard await libraryIsAuthoritative() else { return Self.libraryNotSynced }
        do {
            libraryIcons = try await iconLibrary.add(
                vaultKey: key, current: libraryIcons,
                input: IconInput(label: label, dataUrl: dataUrl, sourceBytes: source))
            requestSync()
            return nil
        } catch let error as IconLibraryError {
            return error.description
        } catch {
            return "Could not save icon"
        }
    }

    func renameLibraryIcon(id: String, label: String) async -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return await changeLibrary { icons in
            icons.map { icon in
                guard icon.id == id else { return icon }
                var copy = icon
                copy.label = trimmed.isEmpty ? "Icon" : trimmed
                return copy
            }
        }
    }

    func removeLibraryIcon(id: String) async -> String? {
        await changeLibrary { $0.filter { $0.id != id } }
    }

    private func changeLibrary(_ change: ([LibraryIcon]) -> [LibraryIcon]) async -> String? {
        guard let key = vaultKey else { return "Vault is locked" }
        guard await libraryIsAuthoritative() else { return Self.libraryNotSynced }
        let next = change(libraryIcons)
        do {
            try await iconLibrary.save(vaultKey: key, icons: next)
            libraryIcons = next
            requestSync()
            return nil
        } catch {
            return "Could not save icon"
        }
    }

    /// Icon downloads use Android's 5 s timeouts.
    private static let fetchIcon: ImportIcons.Fetch = { url in
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        return data
    }

    /// Writes that the UI fires and forgets (settings, reordering) run strictly in the order they
    /// were issued, so two quick changes can't land swapped.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = writeQueue
        writeQueue = Task {
            await previous?.value
            await work()
        }
    }

    private func persist(_ key: String, _ value: String) {
        enqueue { [repository] in try? await repository.setSetting(key, value) }
    }

    /// Waits for queued writes (tests, and anything that must read them back).
    func waitForPendingWrites() async { await writeQueue?.value }

    // MARK: Lifecycle

    /// Auto-lock after the app has been in the background longer than the timeout.
    func scenePhaseChanged(_ newPhase: ScenePhase, now: Date = Date()) {
        switch newPhase {
        case .background:
            backgroundedAt = now
        case .active:
            if phase == .unlocked,
               AutoLock.shouldLock(backgroundedAt: backgroundedAt, now: now, timeout: lockTimeout) {
                lock()
            }
            backgroundedAt = nil
        default:
            break
        }
    }

    // MARK: Feedback

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { toast = nil }
        }
    }

    /// Copy what a tap on `entry` hands out right now: the current code, or the next one in the last
    /// seconds when "Show upcoming code" is on.
    func copyCode(of entry: VaultEntry, now: Date = Date()) {
        guard let pick = LiveCode(entry: entry, now: Int64(now.timeIntervalSince1970))
            .toCopy(showNextCode: showNextCode) else { return }
        Clipboard.copy(pick.code)
        showToast("\(pick.isNext ? "Next code" : "Code") copied — clears in \(Int(Clipboard.clearAfter))s")
        Task { await recordUse(of: entry) }
    }

    func copySecret(of entry: VaultEntry) {
        Clipboard.copy(entry.secret)
        showToast("Secret key copied — clears in \(Int(Clipboard.clearAfter))s")
    }
}

// MARK: - Bootstrap

extension AppModel {
    /// Builds the model on the real on-disk database, or an in-memory one for UI tests
    /// (`-uitest-inmemory`) so each run starts from a fresh, un-set-up vault.
    static func bootstrap(arguments: [String] = ProcessInfo.processInfo.arguments) throws -> AppModel {
        let db: AppDatabase
        if arguments.contains("-uitest-inmemory") {
            db = try AppDatabase.inMemory()
        } else {
            let dir = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("PsTotp", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // The Android app excludes everything from cloud backup / device transfer; do the same.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDir = dir
            try mutableDir.setResourceValues(values)
            db = try AppDatabase.open(at: dir.appendingPathComponent("pstotp.db"))
        }
        let repository = VaultRepository(db: db)
        let biometrics = KeychainBiometricKeyStore()
        // UI tests must never touch the real Keychain or network.
        let inMemory = arguments.contains("-uitest-inmemory")
        let secrets: SecretStore = inMemory ? InMemorySecretStore() : KeychainSecretStore()
        let server = makeServerSession(db: db, repository: repository, biometrics: biometrics, secrets: secrets,
                                       transport: URLSessionTransport())
        return AppModel(repository: repository, iconLibrary: IconLibraryRepository(db: db), biometrics: biometrics, server: server)
    }
}
