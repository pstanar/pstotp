import PsTotpCore
import SwiftUI

/// Sign in to a PsTotp server (Android's `ConnectServerScreen`, password login). Passkey login and
/// account recovery come with their own slices.
struct ConnectView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var serverUrl: String
    @State private var email: String
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var pendingApproval = false
    @State private var showRegister = false
    @FocusState private var focus: Field?

    private enum Field { case server, email, password }

    /// - Parameters: Pre-filled when signing in again to a known account.
    init(model: AppModel, serverUrl: String = "", email: String = "") {
        self.model = model
        _serverUrl = State(initialValue: serverUrl)
        _email = State(initialValue: email)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Connect to a PsTotp server for multi-device sync.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)

                AuthTextField(title: "Server URL (totp.example.com)", text: $serverUrl, keyboard: .URL) { focus = .email }
                    .focused($focus, equals: .server)
                    .accessibilityIdentifier("connect.server")
                AuthTextField(title: "Email", text: $email, keyboard: .emailAddress) { focus = .password }
                    .focused($focus, equals: .email)
                    .accessibilityIdentifier("connect.email")
                PasswordField(title: "Password", text: $password, onSubmit: submit)
                    .focused($focus, equals: .password)
                    .accessibilityIdentifier("connect.password")

                if let error {
                    AuthError(message: error).accessibilityIdentifier("connect.error")
                }
                if pendingApproval {
                    Text("This device is pending approval. Open PsTotp on an already-approved device and approve this device in Settings > Devices.")
                        .font(.footnote)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("connect.pending")
                }

                AuthSubmitButton(title: "Connect", busyTitle: "Connecting…", loading: busy, action: submit)
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("connect.submit")

                Button("Don't have an account? Create one") { showRegister = true }
                    .disabled(busy || ServerURL.normalize(serverUrl) == nil)
                    .padding(.top, 8)
                    .accessibilityIdentifier("connect.register")
            }
            .disabled(busy)
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background)
        .navigationTitle("Connect to Server")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showRegister) {
            RegisterView(model: model, serverUrl: serverUrl, initialEmail: email) {
                showRegister = false
                dismiss()
            }
        }
        .onChange(of: serverUrl) { error = nil }
        .onChange(of: email) { error = nil }
        .onChange(of: password) { error = nil }
    }

    private var canSubmit: Bool {
        !busy && ServerURL.normalize(serverUrl) != nil && !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        busy = true
        error = nil
        pendingApproval = false
        Task {
            switch await model.connect(serverUrl: serverUrl, email: email, password: password) {
            case .connected:
                dismiss()
            case .pendingApproval:
                pendingApproval = true
            case .failed(let message):
                error = message
            }
            busy = false
        }
    }
}
