import PsTotpCore
import SwiftUI

/// Compact tile for the grid: icon, issuer and account. Tap selects (the detail panel shows the
/// code); the corner menu or a long press opens the entry actions.
struct TotpGridTile: View {
    let entry: VaultEntry
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopySecret: () -> Void
    let onShowQR: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ServiceIconView(issuer: entry.issuer, icon: entry.icon, size: 40)
            Text(entry.issuer)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
            if !entry.accountName.isEmpty, entry.accountName != entry.issuer {
                Text(entry.accountName)
                    .font(.caption2)
                    .foregroundStyle(Palette.onSurfaceVariant)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Palette.primaryContainer : Palette.surface,
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            // A one-tap overflow affordance; long press stays available as a fallback.
            Menu { actions } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.onSurfaceVariant)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More options for \(entry.issuer)")
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: onSelect)
        .contextMenu { actions }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: "Select", onSelect)
        .accessibilityIdentifier("tile.\(entry.issuer)")
    }

    private var actions: some View {
        EntryActions(onCopySecret: onCopySecret, onShowQR: onShowQR, onEdit: onEdit, onDelete: onDelete)
    }
}
