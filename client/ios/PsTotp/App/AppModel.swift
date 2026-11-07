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

    private let repository: VaultRepository
    private let iconLibrary: IconLibraryRepository
    private let biometrics: BiometricKeyStore
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

    init(
        repository: VaultRepository, iconLibrary: IconLibraryRepository,
        biometrics: BiometricKeyStore = KeychainBiometricKeyStore()
    ) {
        self.repository = repository
        self.iconLibrary = iconLibrary
        self.biometrics = biometrics
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
                // Keychain items outlive an uninstall; a key left by an earlier install belongs to a
                // vault that no longer exists.
                biometrics.removeKey()
            }
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
            sortUsage = usage
            errorMessage = nil
            phase = .unlocked
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
        importIconSources = [:]
        errorMessage = nil
        if phase == .unlocked { phase = .locked }
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
        guard !items.isEmpty,
              let (icons, result) = try? await iconLibrary.addBatch(vaultKey: key, current: libraryIcons, items: items)
        else { return nil }
        libraryIcons = icons
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
        do {
            libraryIcons = try await iconLibrary.add(
                vaultKey: key, current: libraryIcons,
                input: IconInput(label: label, dataUrl: dataUrl, sourceBytes: source))
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
        let next = change(libraryIcons)
        do {
            try await iconLibrary.save(vaultKey: key, icons: next)
            libraryIcons = next
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
        return AppModel(repository: VaultRepository(db: db), iconLibrary: IconLibraryRepository(db: db))
    }
}
