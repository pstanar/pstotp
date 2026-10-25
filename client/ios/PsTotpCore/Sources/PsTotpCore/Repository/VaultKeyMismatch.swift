import Foundation

/// Thrown by `VaultRepository.getAllEntries` when the supplied vault key decrypts a majority of
/// stored entries to junk. Almost always means the in-memory vault key doesn't match the one the
/// entries were encrypted with — surfacing it prevents the UI from silently showing an empty vault.
public struct VaultKeyMismatchError: Error, Equatable, CustomStringConvertible {
    public let failed: Int
    public let total: Int

    public var description: String {
        "Vault key mismatch: \(failed) of \(total) entries failed to decrypt"
    }
}

/// Decide whether a batch of decrypt failures means the vault key is wrong or is a sporadic
/// per-entry failure.
///
/// Rule: tolerate exactly one failure as long as something decrypted. Anything else — zero
/// successes, or more than one failure — is a mismatch. A pure function so the edge cases are
/// easy to test.
func isVaultKeyMismatch(failures: Int, successes: Int) -> Bool {
    if failures <= 0 { return false }
    if successes == 0 { return true }
    return failures > 1
}
