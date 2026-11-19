import PsTotpCore
import SwiftUI

/// The account's passkeys (Android's `PasskeyManagementScreen`): see, rename and revoke them.
/// Adding a passkey and signing in with one aren't available on iOS yet (they need the platform's
/// passkey ceremony and an Associated Domains entry per server; see DIFFERENCES.md).
struct PasskeysView: View {
    @Bindable var model: AppModel

    @State private var passkeys: [WebAuthnCredentialInfo] = []
    @State private var loading = true
    @State private var error: String?
    @State private var renaming: WebAuthnCredentialInfo?
    @State private var newName = ""
    @State private var revoking: WebAuthnCredentialInfo?

    var body: some View {
        List {
            Section {
                Text("Passkeys let you sign in to the server without a password. Adding a passkey isn't available in this app yet: add one from the web or Android app, then manage it here.")
                    .font(.footnote)
                    .foregroundStyle(Palette.onSurfaceVariant)
                    .accessibilityIdentifier("passkeys.note")
            }
            .listRowBackground(Color.clear)

            if let error {
                Section { AuthError(message: error).accessibilityIdentifier("passkeys.error") }
                    .listRowBackground(Color.clear)
            }

            if loading && passkeys.isEmpty {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
                    .listRowBackground(Color.clear)
            } else if passkeys.isEmpty {
                Section { Text("No passkeys registered yet.").foregroundStyle(Palette.onSurfaceVariant) }
                    .listRowBackground(Palette.surface)
                    .accessibilityIdentifier("passkeys.empty")
            } else {
                Section {
                    ForEach(passkeys, id: \.id) { passkey in
                        HStack(spacing: 12) {
                            Image(systemName: "key.fill").foregroundStyle(Palette.primary).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(passkey.friendlyName ?? "Unnamed passkey")
                                Text(detail(passkey))
                                    .font(.caption)
                                    .foregroundStyle(Palette.onSurfaceVariant)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("passkeys.row.\(passkey.id)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Revoke", role: .destructive) { revoking = passkey }
                                .accessibilityIdentifier("passkeys.revoke.\(passkey.id)")
                            Button("Rename") {
                                newName = passkey.friendlyName ?? ""
                                renaming = passkey
                            }
                            .tint(Palette.primary)
                            .accessibilityIdentifier("passkeys.rename.\(passkey.id)")
                        }
                    }
                }
                .listRowBackground(Palette.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Passkeys")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .alert("Rename Passkey", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let passkey = renaming { act { await model.renamePasskey(id: passkey.id, to: newName) } }
            }
        }
        .confirmationDialog(
            "Revoke \"\(revoking?.friendlyName ?? "Unnamed passkey")\"?",
            isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
            titleVisibility: .visible
        ) {
            Button("Revoke", role: .destructive) {
                if let passkey = revoking { act { await model.revokePasskey(id: passkey.id) } }
            }
        } message: {
            Text("You won't be able to sign in with it anymore.")
        }
    }

    private func detail(_ passkey: WebAuthnCredentialInfo) -> String {
        var text = "Created \(ServerTime.day(passkey.createdAt))"
        if let used = passkey.lastUsedAt { text += " · Used \(ServerTime.day(used))" }
        return text
    }

    private func load() async {
        switch await model.loadPasskeys() {
        case .success(let loaded):
            passkeys = loaded
            error = nil
        case .failure(let failure):
            error = failure.message
        }
        loading = false
    }

    /// Runs a change, then refreshes the list; a failure is shown above it.
    private func act(_ action: @escaping () async -> String?) {
        Task {
            let problem = await action()
            await load()
            if let problem { error = problem }
        }
    }
}
