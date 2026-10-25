import PsTotpCore
import SwiftUI

struct AddAccountView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case manual = "Manual"
        case uri = "Paste URI"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .manual
    @State private var error: String?
    @State private var saving = false

    // Manual
    @State private var issuer = ""
    @State private var accountName = ""
    @State private var secret = ""
    @State private var showAdvanced = false
    @State private var algorithm = "SHA1"
    @State private var digits = "6"
    @State private var period = "30"

    // URI
    @State private var uri = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Method", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                switch mode {
                case .manual: manualFields
                case .uri: uriFields
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Palette.error)
                            .accessibilityIdentifier("add.error")
                    }
                    .listRowBackground(Palette.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: save)
                        .disabled(saving || !canSave)
                        .accessibilityIdentifier("add.submit")
                }
            }
            .onChange(of: mode) { error = nil }
        }
    }

    // MARK: Manual

    @ViewBuilder private var manualFields: some View {
        Section {
            TextField("Issuer (e.g. GitHub)", text: $issuer)
                .accessibilityIdentifier("add.issuer")
            TextField("Account (e.g. you@example.com)", text: $accountName)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .accessibilityIdentifier("add.account")
            TextField("Secret key", text: $secret)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .accessibilityIdentifier("add.secret")
        }
        .listRowBackground(Palette.surface)
        Section {
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                Picker("Algorithm", selection: $algorithm) {
                    Text("SHA-1 (default)").tag("SHA1")
                    Text("SHA-256").tag("SHA256")
                    Text("SHA-512").tag("SHA512")
                }
                LabeledContent("Digits") {
                    TextField("6", text: $digits).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Period (sec)") {
                    TextField("30", text: $period).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
            }
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: URI

    @ViewBuilder private var uriFields: some View {
        Section {
            TextField("otpauth://totp/Issuer:account?secret=…", text: $uri, axis: .vertical)
                .lineLimit(3...6)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.footnote, design: .monospaced))
                .accessibilityIdentifier("add.uri")
            // PasteButton reads the clipboard without iOS's "Allow Paste" prompt.
            PasteButton(payloadType: String.self) { strings in
                if let first = strings.first { uri = first; error = nil }
            }
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: Save

    private var canSave: Bool {
        switch mode {
        case .manual: !secret.trimmingCharacters(in: .whitespaces).isEmpty
        case .uri: !uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func save() {
        let plaintext: VaultEntryPlaintext
        do {
            switch mode {
            case .manual:
                plaintext = try EntryValidation.manualEntry(
                    issuer: issuer, accountName: accountName, secret: secret,
                    algorithm: algorithm, digits: digits, period: period)
            case .uri:
                plaintext = try OtpauthUri.parse(uri.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } catch {
            self.error = String(describing: error)
            return
        }

        saving = true
        Task {
            let failure = await model.addEntry(plaintext)
            saving = false
            if let failure { error = failure } else { dismiss() }
        }
    }
}
