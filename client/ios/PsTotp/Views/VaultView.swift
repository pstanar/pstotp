import PsTotpCore
import SwiftUI

struct VaultView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var showingAdd = false
    @State private var pendingDeletion: VaultEntry?
    @State private var qrEntry: VaultEntry?
    @State private var editingEntry: VaultEntry?
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            Group {
                if model.entries.isEmpty {
                    EmptyVaultView()
                } else {
                    let shown = model.displayEntries(query: query)
                    Group {
                        if model.layoutMode == .grid { grid(shown) } else { list(shown) }
                    }
                    .searchable(text: $query, prompt: "Search accounts")
                    .overlay {
                        if shown.isEmpty { ContentUnavailableView.search(text: query) }
                    }
                }
            }
            .navigationTitle("PsTotp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if editMode.isEditing {
                        Button("Done") { editMode = .inactive }
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("vault.done")
                    } else {
                        Button("Lock", systemImage: "lock") { model.lock() }
                            .accessibilityIdentifier("vault.lock")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    layoutToggle
                    sortMenu
                    Button("Add account", systemImage: "plus") { showingAdd = true }
                        .accessibilityIdentifier("vault.add")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
        }
        .sheet(isPresented: $showingAdd) { AddAccountView(model: model) }
        .sheet(item: $qrEntry) { QRCodeSheet(entry: $0) }
        .sheet(item: $editingEntry) { EditAccountView(model: model, entry: $0) }
        .alert(
            "Delete Account",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { entry in
            Button("Delete", role: .destructive) { Task { await model.deleteEntry(id: entry.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text("Delete \(entry.issuer)? This cannot be undone.")
        }
    }

    /// Dragging only makes sense in the list, in the user's own (manual) order, with something to move.
    private var canReorder: Bool {
        model.sortMode == .manual && model.layoutMode == .list && model.entries.count > 1
    }

    private func list(_ shown: [VaultEntry]) -> some View {
        List {
            ForEach(shown) { entry in
                TotpCard(
                    entry: entry,
                    onCopyCode: { model.copyCode($0, for: entry) },
                    onCopySecret: { model.copySecret(of: entry) },
                    onShowQR: { qrEntry = entry },
                    onEdit: { editingEntry = entry },
                    onDelete: { pendingDeletion = entry })
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = entry }
                }
            }
            .onMove(perform: canReorder ? { source, destination in
                model.moveEntries(shownIds: shown.map(\.id), fromOffsets: source, toOffset: destination)
            } : nil)
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .onChange(of: canReorder) { _, allowed in if !allowed { editMode = .inactive } }
        .accessibilityIdentifier("vault.list")
    }

    private func grid(_ shown: [VaultEntry]) -> some View {
        VaultGridView(
            model: model,
            entries: shown,
            onShowQR: { qrEntry = $0 },
            onEdit: { editingEntry = $0 },
            onDelete: { pendingDeletion = $0 }
        )
    }

    private var layoutToggle: some View {
        let isList = model.layoutMode == .list
        return Button(isList ? "Grid view" : "List view",
                      systemImage: isList ? "square.grid.2x2" : "list.bullet") {
            model.setLayoutMode(isList ? .grid : .list)
        }
        .accessibilityIdentifier("vault.layout")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: Binding(get: { model.sortMode }, set: model.setSortMode)) {
                ForEach(SortMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Divider()
            Picker("Direction", selection: Binding(get: { model.sortReversed }, set: model.setSortReversed)) {
                Label("Natural", systemImage: "arrow.down").tag(false)
                Label("Reversed", systemImage: "arrow.up").tag(true)
            }
            .disabled(model.sortMode == .manual)   // reversal doesn't apply to the user's own order
            if canReorder {
                Divider()
                Button("Reorder Accounts", systemImage: "line.3.horizontal") { editMode = .active }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort")
        .accessibilityIdentifier("vault.sort")
    }
}

private struct EmptyVaultView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Welcome to PsTotp").font(.title2)
            Text("Tap + to add your first account")
                .font(.subheadline)
                .foregroundStyle(Palette.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("vault.empty")
    }
}
