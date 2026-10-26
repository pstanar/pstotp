import SwiftUI

struct SetupView: View {
    @Bindable var model: AppModel
    @State private var password = ""
    @State private var confirm = ""
    @State private var loading = false
    @FocusState private var focus: Field?

    private enum Field { case password, confirm }

    var body: some View {
        VStack(spacing: 0) {
            AuthHeader(subtitle: "Create a password to protect your vault")

            VStack(spacing: 12) {
                PasswordField(title: "Password", text: $password, submitLabel: .next) { focus = .confirm }
                    .focused($focus, equals: .password)
                    .accessibilityIdentifier("setup.password")
                PasswordField(title: "Confirm Password", text: $confirm, submitLabel: .done, onSubmit: submit)
                    .focused($focus, equals: .confirm)
                    .accessibilityIdentifier("setup.confirm")
            }
            .disabled(loading)

            if let error = model.errorMessage {
                AuthError(message: error)
                    .accessibilityIdentifier("setup.error")
            }

            AuthSubmitButton(title: "Create Vault", busyTitle: "Creating vault…", loading: loading, action: submit)
                .disabled(loading || password.isEmpty)
                .accessibilityIdentifier("setup.create")
        }
        .padding(24)
        .frame(maxHeight: .infinity)
        .onChange(of: password) { model.errorMessage = nil }
        .onChange(of: confirm) { model.errorMessage = nil }
    }

    private func submit() {
        guard !loading, !password.isEmpty else { return }
        loading = true
        Task {
            _ = await model.setupPassword(password, confirm: confirm)
            loading = false
        }
    }
}
