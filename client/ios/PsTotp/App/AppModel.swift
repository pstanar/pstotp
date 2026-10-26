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

    /// Shown on the setup / unlock screens.
    var errorMessage: String?
    /// Transient confirmation ("Code copied").
    private(set) var toast: String?

    private let repository: VaultRepository
    private var vaultKey: Data?
    private var usage: [String: EntryUsageRecord] = [:]
    /// Usage as of the last (re)sort. Copying a code records usage but must not re-sort the list
    /// mid-session, or the row would jump under the user's finger (same rule as Android).
    private var sortUsage: [String: EntryUsageRecord] = [:]
    private var backgroundedAt: Date?
    private var toastTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?

    init(repository: VaultRepository) {
        self.repository = repository
    }

    // MARK: Startup

    func start() async {
        guard phase == .loading else { return }
        do {
            let setUp = try await repository.isSetUp()
            sortMode = SortMode.fromStorageKey(try await repository.getSetting(SettingsKeys.sortMode))
            sortReversed = try await repository.getSetting(SettingsKeys.sortReversed) == "true"
            layoutMode = LayoutMode.fromStorageKey(try await repository.getSetting(SettingsKeys.layoutMode))
            lockTimeout = LockTimeout.fromMillis(
                try await repository.getSetting(SettingsKeys.lockTimeoutMs).flatMap { Int64($0) })
            usage = Dictionary(uniqueKeysWithValues: try await repository.getAllUsage().map { ($0.entryId, $0) })
            sortUsage = usage
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
            // Decrypt before touching any state: a wrong-key failure must not leave the UI
            // "unlocked" with no entries.
            let decrypted = try await repository.getAllEntries(vaultKey: key)
            vaultKey = key
            entries = decrypted
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
        if var key = vaultKey {
            key.resetBytes(in: 0..<key.count)   // best effort: Data may have been copied
        }
        vaultKey = nil
        entries = []
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

    /// Rename an entry (service name and account). Secret, algorithm, icon and order are untouched.
    /// An edit that changes nothing is not written, so it doesn't queue a pointless sync.
    /// - Returns: nil on success, otherwise a message for the user.
    func updateEntry(_ entry: VaultEntry, issuer: String, accountName: String) async -> String? {
        guard let key = vaultKey else { return "Vault is locked" }
        let edited = EntryValidation.edited(entry, issuer: issuer, accountName: accountName)
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
            usage = Dictionary(uniqueKeysWithValues: try await repository.getAllUsage().map { ($0.entryId, $0) })
        } catch {
            // Usage stats are best-effort; never interrupt the user over them.
        }
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
        persist(SettingsKeys.sortMode, mode.storageKey)
    }

    func setSortReversed(_ reversed: Bool) {
        sortReversed = reversed
        sortUsage = usage
        persist(SettingsKeys.sortReversed, String(reversed))
    }

    func setLayoutMode(_ mode: LayoutMode) {
        layoutMode = mode
        persist(SettingsKeys.layoutMode, mode.storageKey)
    }

    func setLockTimeout(_ timeout: LockTimeout) {
        lockTimeout = timeout
        persist(SettingsKeys.lockTimeoutMs, String(timeout.millis))
    }

    /// Settings writes are fire-and-forget from the UI, but chained so they land in order.
    private func persist(_ key: String, _ value: String) {
        let previous = persistTask
        persistTask = Task {
            await previous?.value
            try? await repository.setSetting(key, value)
        }
    }

    /// Waits for queued settings writes (tests, and anything that must read them back).
    func waitForPendingWrites() async { await persistTask?.value }

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

    func copyCode(_ code: String, for entry: VaultEntry) {
        Clipboard.copy(code)
        showToast("Code copied — clears in \(Int(Clipboard.clearAfter))s")
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
        return AppModel(repository: VaultRepository(db: db))
    }
}
