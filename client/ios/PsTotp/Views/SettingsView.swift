import PsTotpCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings (Android's `SettingsScreen`, standalone parts): auto-lock, import & export, server sync,
/// about. Pushed from the vault screen.
struct SettingsView: View {
    @Bindable var model: AppModel

    @State private var showingExport = false
    @State private var showingImporter = false
    @State private var pendingEncryptedImport: String?
    @State private var importPassword = ""
    @State private var importCandidates: ImportCandidatesBox?
    @State private var importError: String?
    @State private var working = false
    @State private var biometricError: String?
    @State private var changingBiometrics = false

    var body: some View {
        Form {
            if let biometry = model.biometry {
                Section {
                    Toggle(isOn: Binding(get: { model.biometricEnabled }, set: setBiometrics)) {
                        Text("Unlock with \(biometry.name)")
                    }
                    .disabled(changingBiometrics)
                    .accessibilityIdentifier("settings.biometric")
                } header: {
                    Text("Security")
                } footer: {
                    if let biometricError {
                        Text(biometricError).foregroundStyle(Palette.error)
                    } else {
                        Text("Unlock the vault with \(biometry.name) instead of your password.")
                    }
                }
                .listRowBackground(Palette.surface)
            }

            Section {
                Picker("Auto-lock", selection: Binding(get: { model.lockTimeout }, set: model.setLockTimeout)) {
                    ForEach(LockTimeout.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .accessibilityIdentifier("settings.autoLock")
            } header: {
                if model.biometry == nil { Text("Security") }
            } footer: {
                Text("Lock the vault after this long in the background.")
            }
            .listRowBackground(Palette.surface)

            Section {
                Button("Export…") { showingExport = true }
                    .accessibilityIdentifier("settings.export")
                Button("Import…") { showingImporter = true }
                    .accessibilityIdentifier("settings.import")
            } header: {
                Text("Import & Export")
            } footer: {
                Text("Export your vault or import from another authenticator.")
            }
            .listRowBackground(Palette.surface)
            .disabled(working)

            Section("Server Sync") {
                Text("Connect to a PsTotp server for multi-device sync.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.onSurfaceVariant)
            }
            .listRowBackground(Palette.surface)

            Section("About") {
                LabeledContent("Version", value: Self.version)
                    .accessibilityIdentifier("settings.version")
                Text("TOTP authenticator with encrypted multi-device sync")
                    .font(.subheadline)
                    .foregroundStyle(Palette.onSurfaceVariant)
            }
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if working { ImportProgressView(progress: model.importIconProgress) } }
        .sheet(isPresented: $showingExport) { ExportView(model: model) }
        .sheet(item: $importCandidates) { box in
            ImportPreviewView(model: model, candidates: box.candidates)
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json, .plainText, .text]) { result in
            switch result {
            case .success(let url): readImportFile(url)
            case .failure(let error): importError = "Failed to read file: \(error.localizedDescription)"
            }
        }
        .alert("Decrypt Import", isPresented: Binding(
            get: { pendingEncryptedImport != nil },
            set: { if !$0 { pendingEncryptedImport = nil; importPassword = "" } })
        ) {
            SecureField("Password", text: $importPassword)
                .accessibilityIdentifier("import.password")
            Button("Decrypt") {
                if let content = pendingEncryptedImport { prepare(content, password: importPassword) }
            }
            .disabled(importPassword.isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This file is encrypted.")
        }
        .alert("Import Failed", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private func setBiometrics(_ enabled: Bool) {
        changingBiometrics = true
        biometricError = nil
        Task {
            biometricError = await model.setBiometricEnabled(enabled)
            changingBiometrics = false
        }
    }

    private func readImportFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            importError = "Failed to read file"
            return
        }
        prepare(content, password: nil)
    }

    private func prepare(_ content: String, password: String?) {
        working = true
        Task {
            let outcome = await model.prepareImport(content, password: password)
            working = false
            switch outcome {
            case .ready(let candidates): importCandidates = ImportCandidatesBox(candidates: candidates)
            case .needsPassword: pendingEncryptedImport = content
            case .failed(let message): importError = message
            }
        }
    }

    private static let version =
        Bundle.main.object(forInfoDictionaryKey: "PsTotpVersionLabel") as? String ?? "unknown"
}

/// `sheet(item:)` needs an identity; each prepared import is a new one.
private struct ImportCandidatesBox: Identifiable {
    let id = UUID()
    let candidates: [ImportCandidate]
}

private struct ImportProgressView: View {
    let progress: (done: Int, total: Int)?

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            if let progress {
                Text("Downloading icons")
                Text("\(progress.done) / \(progress.total)").monospacedDigit()
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("import.progress")
    }
}

// MARK: - Export

private struct ExportView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var format: ExportFormat = .encrypted
    @State private var password = ""
    @State private var error: String?
    @State private var exporting = false
    @State private var document: ExportDocument?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Format", selection: $format) {
                        ForEach(ExportFormat.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("export.format")
                } header: {
                    Text("Format")
                } footer: {
                    if format.revealsSecrets {
                        Text("TOTP secrets will be visible in the file.")
                            .foregroundStyle(Palette.error)
                    }
                }
                .listRowBackground(Palette.surface)

                if format.needsPassword {
                    Section("Export Password") {
                        PasswordField(title: "Export Password", text: $password, onSubmit: export)
                            .accessibilityIdentifier("export.password")
                    }
                    .listRowBackground(Palette.surface)
                }

                if let error {
                    Section { AuthError(message: error) }
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Export Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if exporting {
                        ProgressView()
                    } else {
                        Button("Export", action: export)
                            .disabled(format.needsPassword && password.isEmpty)
                            .accessibilityIdentifier("export.confirm")
                    }
                }
            }
            .fileExporter(
                isPresented: Binding(get: { document != nil }, set: { if !$0 { document = nil } }),
                document: document,
                contentType: format == .otpauth ? .plainText : .json,
                defaultFilename: format.fileName
            ) { result in
                switch result {
                case .success:
                    model.showToast("Vault exported")
                    dismiss()
                case .failure(let failure):
                    error = "Export failed: \(failure.localizedDescription)"
                }
            }
        }
    }

    private func export() {
        guard !exporting, !(format.needsPassword && password.isEmpty) else { return }
        exporting = true
        error = nil
        Task {
            switch await model.exportVault(format: format, password: password) {
            case .file(let text): document = ExportDocument(text: text)
            case .failed(let message): error = message
            }
            exporting = false
        }
    }
}

private struct ExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .plainText]
    let text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

// MARK: - Import preview

/// The parsed file, duplicates flagged, with a per-duplicate action (Android's `ImportPreviewDialog`).
private struct ImportPreviewView: View {
    @Bindable var model: AppModel
    @State var candidates: [ImportCandidate]
    @Environment(\.dismiss) private var dismiss

    @State private var duplicateAction: ImportAction = .overwrite
    @State private var importing = false
    @State private var error: String?

    private var duplicateCount: Int { candidates.count(where: \.isDuplicate) }
    private var activeCount: Int { candidates.count { $0.action != .skip } }

    private var title: String {
        var title = "\(candidates.count) entries found"
        if duplicateCount > 0 { title += " (\(duplicateCount) duplicate\(duplicateCount == 1 ? "" : "s"))" }
        return title
    }

    var body: some View {
        NavigationStack {
            Form {
                if duplicateCount > 0 {
                    Section("Duplicates") {
                        Picker("Duplicates", selection: $duplicateAction) {
                            ForEach(ImportAction.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("import.duplicateAction")
                        .onChange(of: duplicateAction) { _, action in
                            candidates = ImportCandidate.settingDuplicateAction(action, in: candidates)
                        }
                    }
                    .listRowBackground(Palette.surface)
                }

                Section {
                    ForEach(candidates.indices, id: \.self) { index in
                        CandidateRow(candidate: $candidates[index])
                    }
                }
                .listRowBackground(Palette.surface)

                if let error {
                    Section { AuthError(message: error) }
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(importing)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(importing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(importing ? "Importing…" : "Import \(activeCount)") {
                        importing = true
                        Task {
                            error = await model.confirmImport(candidates)
                            importing = false
                            if error == nil { dismiss() }
                        }
                    }
                    .disabled(activeCount == 0 || importing)
                    .accessibilityIdentifier("import.confirm")
                }
            }
        }
    }
}

private struct CandidateRow: View {
    @Binding var candidate: ImportCandidate

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.imported.accountName.isEmpty
                     ? candidate.imported.issuer
                     : "\(candidate.imported.issuer) — \(candidate.imported.accountName)")
                    .foregroundStyle(candidate.action == .skip ? Palette.onSurfaceVariant.opacity(0.4) : Palette.onBackground)
                if candidate.isDuplicate {
                    Text("DUPLICATE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.primary)
                }
            }
            Spacer()
            if candidate.isDuplicate {
                Menu(candidate.action.label) {
                    Picker("Action", selection: $candidate.action) {
                        ForEach(ImportAction.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                .font(.subheadline)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("import.candidate")
    }
}
