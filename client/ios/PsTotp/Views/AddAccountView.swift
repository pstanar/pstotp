import PhotosUI
import PsTotpCore
import SwiftUI

struct AddAccountView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case scan = "Scan QR"
        case image = "Image"
        case manual = "Manual"
        case uri = "Paste URI"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .scan
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

    // Image
    @State private var photo: PhotosPickerItem?

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
                case .scan: scanSection
                case .image: imageSection
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
                // Scan and Image add the account the moment a code is read, so only the typed
                // methods need an explicit Add.
                if mode == .manual || mode == .uri {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add", action: save)
                            .disabled(saving || !canSave)
                            .accessibilityIdentifier("add.submit")
                    }
                }
            }
            .onChange(of: mode) { error = nil }
        }
    }

    // MARK: Scan

    @ViewBuilder private var scanSection: some View {
        Section {
            QRScannerView { code in addFromCodes([code]) }
                .listRowInsets(EdgeInsets())
        } footer: {
            Text("Point your camera at a QR code")
        }
    }

    // MARK: Image

    @ViewBuilder private var imageSection: some View {
        Section {
            VStack(spacing: 14) {
                Image(systemName: "photo")
                    .font(.system(size: 44))
                    .foregroundStyle(Palette.onSurfaceVariant)
                PhotosPicker(selection: $photo, matching: .images) {
                    Text("Select image with QR code")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("add.pickImage")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .listRowBackground(Color.clear)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            addFromPhoto(item)
        }
    }

    private func addFromPhoto(_ item: PhotosPickerItem) {
        error = nil
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                error = QRImport.Failure.unreadableImage.description
                return
            }
            // Decoding a large photo is CPU work; keep it off the main actor.
            let result = await Task.detached(priority: .userInitiated) {
                Result { try QRImport.entry(fromImageData: data) }
            }.value
            await store(result)
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
        case .scan, .image: false
        }
    }

    private func save() {
        let result = Result<VaultEntryPlaintext, Error> {
            switch mode {
            case .manual:
                try EntryValidation.manualEntry(
                    issuer: issuer, accountName: accountName, secret: secret,
                    algorithm: algorithm, digits: digits, period: period)
            case .uri:
                try OtpauthUri.parse(uri.trimmingCharacters(in: .whitespacesAndNewlines))
            case .scan, .image:
                preconditionFailure("scan and image add via addFromCodes / addFromPhoto")
            }
        }
        Task { await store(result) }
    }

    private func addFromCodes(_ codes: [String]) {
        Task { await store(Result { try QRImport.entry(fromCodes: codes) }) }
    }

    /// Adds a parsed entry, or shows why it couldn't be added. Ignores codes seen while a save is
    /// in flight so a burst of camera frames can't add the same account twice.
    private func store(_ result: Result<VaultEntryPlaintext, Error>) async {
        guard !saving else { return }
        switch result {
        case .failure(let failure):
            error = String(describing: failure)
        case .success(let plaintext):
            saving = true
            let failure = await model.addEntry(plaintext)
            saving = false
            if let failure { error = failure } else { dismiss() }
        }
    }
}
