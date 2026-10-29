import PsTotpCore
import SwiftUI

/// One vault row: service icon in a countdown ring, issuer, account, and the live code.
/// Tapping anywhere copies the code (Authy-style), like the Android card. With "Show upcoming code"
/// on, the next code is previewed in the last seconds (see `LiveCode`).
struct TotpCard: View {
    let entry: VaultEntry
    let showNextCode: Bool
    /// Copy whatever the entry hands out right now (the owner decides current vs next).
    let onCopyCode: () -> Void
    let onCopySecret: () -> Void
    let onShowQR: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.editMode) private var editMode
    private var isReordering: Bool { editMode?.wrappedValue.isEditing == true }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let live = LiveCode(entry: entry, now: Int64(context.date.timeIntervalSince1970))
            let code = live.code
            let timeLeft = live.timeLeft

            HStack(spacing: 12) {
                CountdownRing(period: entry.period, size: 48) {
                    ServiceIconView(issuer: entry.issuer, icon: entry.icon, size: 36)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.issuer)
                        .font(.title3)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .lineLimit(1)
                    if !entry.accountName.isEmpty {
                        Text(entry.accountName)
                            .font(.caption)
                            .foregroundStyle(Palette.onSurfaceVariant.opacity(0.8))
                            .lineLimit(1)
                    }
                    HStack(spacing: 12) {
                        CodeText(code: code, size: 28)
                            .accessibilityIdentifier("code")
                        if code != nil, timeLeft <= 10 {
                            Text("\(timeLeft)s")
                                .font(.footnote)
                                .foregroundStyle(timeLeft <= 5 ? Palette.error : Palette.onSurfaceVariant)
                                .monospacedDigit()
                        }
                    }
                    if let next = live.preview(enabled: showNextCode) {
                        NextCodeText(code: next, size: 16)
                    }
                }

                Spacer(minLength: 0)

                // The system draws its drag handle at the trailing edge while reordering.
                if !isReordering { optionsMenu }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture { if !isReordering, code != nil { onCopyCode() } }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Copy code") { if code != nil { onCopyCode() } }
        }
        .accessibilityIdentifier("card.\(entry.issuer)")
    }

    private var optionsMenu: some View {
        Menu {
            EntryActions(onCopySecret: onCopySecret, onShowQR: onShowQR, onEdit: onEdit, onDelete: onDelete)
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 32, height: 44)
                .foregroundStyle(Palette.onSurfaceVariant)
        }
        .accessibilityLabel("More options for \(entry.issuer)")
    }
}
