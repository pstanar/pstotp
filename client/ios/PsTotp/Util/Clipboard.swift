import UIKit
import UniformTypeIdentifiers

/// Sensitive-value clipboard handling.
///
/// Android clears the clipboard with a delayed handler, which only works while the process is alive.
/// iOS lets us attach an expiration date to the pasteboard item, so the system clears it even if the
/// app is suspended. `localOnly` keeps codes off Universal Clipboard (other devices).
enum Clipboard {
    static let clearAfter: TimeInterval = 30

    static func copy(_ text: String) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: text]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(clearAfter),
            ])
    }
}
