import PsTotpCore
import SwiftUI

/// One vault row: service icon in a countdown ring, issuer, account, and the live code.
/// Tapping anywhere copies the code (Authy-style), like the Android card.
struct TotpCard: View {
    let entry: VaultEntry
    let onCopyCode: (String) -> Void
    let onCopySecret: () -> Void
    let onShowQR: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.editMode) private var editMode
    private var isReordering: Bool { editMode?.wrappedValue.isEditing == true }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = Int64(context.date.timeIntervalSince1970)
            let code = entry.code(at: now)
            let timeLeft = TotpGenerator.timeRemaining(period: entry.period, now: now)

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
                }

                Spacer(minLength: 0)

                // The system draws its drag handle at the trailing edge while reordering.
                if !isReordering { optionsMenu }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture { if !isReordering, let code { onCopyCode(code) } }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Copy code") { if let code { onCopyCode(code) } }
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
