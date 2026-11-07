import PsTotpCore
import SwiftUI

/// Edit an account: service name, (optional) account and icon.
struct EditAccountView: View {
    @Bindable var model: AppModel
    let entry: VaultEntry
    @Environment(\.dismiss) private var dismiss

    @State private var issuer: String
    @State private var accountName: String
    @State private var icon: String?
    @State private var error: String?
    @State private var saving = false

    init(model: AppModel, entry: VaultEntry) {
        self.model = model
        self.entry = entry
        _issuer = State(initialValue: entry.issuer)
        _accountName = State(initialValue: entry.accountName)
        _icon = State(initialValue: entry.icon)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Headers, not just placeholders: once a field is filled nothing else says what it is.
                Section("Service Name") {
                    TextField("Service Name", text: $issuer)
                        .accessibilityIdentifier("edit.issuer")
                }
                .listRowBackground(Palette.surface)

                Section("Account (optional)") {
                    TextField("Account (optional)", text: $accountName)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("edit.account")
                }
                .listRowBackground(Palette.surface)

                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Palette.error)
                            .accessibilityIdentifier("edit.error")
                    }
                    .listRowBackground(Palette.surface)
                }

                IconPicker(model: model, issuer: issuer, icon: $icon)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(saving)
                        .accessibilityIdentifier("edit.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
        // Locked or deleted underneath us (auto-lock, delete from elsewhere): nothing left to edit.
        .onChange(of: model.entry(id: entry.id) == nil) { _, gone in if gone { dismiss() } }
    }

    private func save() {
        saving = true
        Task {
            let failure = await model.updateEntry(entry, issuer: issuer, accountName: accountName, icon: icon)
            saving = false
            if let failure { error = failure } else { dismiss() }
        }
    }
}
