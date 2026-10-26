import PsTotpCore
import SwiftUI

/// The grid layout: a detail panel for the selected entry above an adaptive grid of tiles.
struct VaultGridView: View {
    let model: AppModel
    let entries: [VaultEntry]
    let onShowQR: (VaultEntry) -> Void
    let onEdit: (VaultEntry) -> Void
    let onDelete: (VaultEntry) -> Void

    @State private var selectedId: String?

    private var selected: VaultEntry? {
        entries.first { $0.id == selectedId } ?? entries.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if let selected {
                TotpGridDetail(entry: selected) { model.copyCode($0, for: selected) }
                    .id(selected.id)                       // fresh ring/code state per entry
                Divider().overlay(Palette.outline)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                    ForEach(entries) { entry in
                        TotpGridTile(
                            entry: entry,
                            isSelected: entry.id == selected?.id,
                            onSelect: { selectedId = entry.id },
                            onCopySecret: { model.copySecret(of: entry) },
                            onShowQR: { onShowQR(entry) },
                            onEdit: { onEdit(entry) },
                            onDelete: { onDelete(entry) })
                    }
                }
                .padding(12)
            }
            .accessibilityIdentifier("vault.grid")
        }
        // Keep a valid selection as search / delete / sort change what is visible (Android does the
        // same in a LaunchedEffect on the filtered list).
        .onChange(of: entries.map(\.id), initial: true) { _, ids in
            selectedId = EntryListing.selection(current: selectedId, in: ids)
        }
    }
}
