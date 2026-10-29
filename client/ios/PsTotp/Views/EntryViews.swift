import PsTotpCore
import SwiftUI

/// A live code, grouped and monospaced, or "Invalid secret" when the entry can't produce one.
/// Shared by the list card and the grid detail panel.
struct CodeText: View {
    let code: String?
    let size: CGFloat

    var body: some View {
        if let code {
            Text(CodeFormat.grouped(code))
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .tracking(2)
                .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
        } else {
            Label("Invalid secret", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(Palette.error)
        }
    }
}

/// The faded "next 123 456" preview under the current code (Android's next-code row).
struct NextCodeText: View {
    let code: String
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("next").font(.caption2)
            Text(CodeFormat.grouped(code))
                .font(.system(size: size, weight: .medium, design: .monospaced))
                .tracking(1)
        }
        .foregroundStyle(Palette.onSurfaceVariant.opacity(0.6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next code \(code.map(String.init).joined(separator: " "))")
        .accessibilityIdentifier("code.next")
    }
}

/// The per-entry actions, shared by the list card's menu and the grid tile's menu / context menu.
struct EntryActions: View {
    let onCopySecret: () -> Void
    let onShowQR: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button("Copy Secret Key", systemImage: "key", action: onCopySecret)
        Button("Show QR Code", systemImage: "qrcode", action: onShowQR)
        Button("Edit", systemImage: "pencil", action: onEdit)
        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
    }
}
