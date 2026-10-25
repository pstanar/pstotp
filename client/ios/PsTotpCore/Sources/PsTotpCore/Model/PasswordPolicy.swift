import Foundation

/// Master-password rules, identical to the Android `SetupScreen` (and the web client).
public enum PasswordPolicy {
    /// - Returns: a user-facing message for the first rule violated, or nil when acceptable.
    public static func validate(_ password: String, confirm: String) -> String? {
        if password.count < 8 { return "Password must be at least 8 characters" }
        if !password.contains(where: \.isUppercase) { return "Must contain an uppercase letter" }
        if !password.contains(where: \.isLowercase) { return "Must contain a lowercase letter" }
        if !password.contains(where: \.isNumber) { return "Must contain a number" }
        if !password.contains(where: { !($0.isLetter || $0.isNumber) }) { return "Must contain a special character" }
        if password != confirm { return "Passwords do not match" }
        return nil
    }
}
