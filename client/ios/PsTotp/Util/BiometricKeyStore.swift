import Foundation
import LocalAuthentication
import Security

/// The device's biometric sensor, when one is enrolled.
enum BiometryKind: Equatable, Sendable {
    case faceID, touchID, opticID

    var name: String {
        switch self {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        }
    }

    var systemImage: String {
        switch self {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        }
    }
}

enum BiometricError: Error, Equatable {
    /// The user dismissed the prompt or chose "Use password"; not worth a message.
    case cancelled
    case failed(String)
}

/// Keeps a copy of the vault key that only a biometric match can read (Android's `KeystoreHelper`
/// + `BiometricHelper`). Injected into `AppModel` so tests can use a fake.
protocol BiometricKeyStore: Sendable {
    /// The enrolled biometry, or nil when there is no sensor or nothing is enrolled.
    func availableBiometry() -> BiometryKind?
    /// Whether a key is stored, without prompting.
    func hasStoredKey() -> Bool
    /// Prompt, then store `vaultKey` (replacing any earlier one).
    func enroll(vaultKey: Data, reason: String) async throws
    /// Prompt and read the key. Nil when there is no usable key — never stored, or invalidated
    /// because the enrolled faces / fingers changed.
    func loadVaultKey(reason: String) async throws -> Data?
    func removeKey()
}

/// The vault key in a Keychain item guarded by `.biometryCurrentSet`: only this device, never in
/// a backup, and unreadable once biometric enrollment changes (Android's
/// `setInvalidatedByBiometricEnrollment(true)`). Biometrics only, no passcode fallback — Android's
/// `BIOMETRIC_STRONG`.
struct KeychainBiometricKeyStore: BiometricKeyStore {
    private let service = "io.github.pstanar.pstotp.biometric"
    private let account = "vault-key"

    func availableBiometry() -> BiometryKind? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return nil
        }
    }

    func hasStoredKey() -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        var query = baseQuery
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // A protected item can't be read without the prompt, but it is there.
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    func enroll(vaultKey: Data, reason: String) async throws {
        let context = try await authenticatedContext(reason: reason)
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, &error)
        else { throw BiometricError.failed("Could not create the key's access control") }

        removeKey()
        var item = baseQuery
        item[kSecValueData as String] = vaultKey
        item[kSecAttrAccessControl as String] = access
        item[kSecUseAuthenticationContext as String] = context
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw BiometricError.failed(Self.describe(status)) }
    }

    func loadVaultKey(reason: String) async throws -> Data? {
        guard hasStoredKey() else { return nil }
        // Authenticate first so a cancel comes back as a clear LAError, then read with that
        // context (no second prompt).
        let context = try await authenticatedContext(reason: reason)
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound, errSecAuthFailed: return nil   // invalidated by an enrollment change
        case errSecUserCanceled: throw BiometricError.cancelled
        default: throw BiometricError.failed(Self.describe(status))
        }
    }

    func removeKey() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func authenticatedContext(reason: String) async throws -> LAContext {
        let context = LAContext()
        context.localizedFallbackTitle = "Use password"
        context.localizedCancelTitle = "Cancel"
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            return context
        } catch let error as LAError where [.userCancel, .userFallback, .systemCancel, .appCancel].contains(error.code) {
            throw BiometricError.cancelled
        } catch {
            throw BiometricError.failed(error.localizedDescription)
        }
    }

    private static func describe(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}
