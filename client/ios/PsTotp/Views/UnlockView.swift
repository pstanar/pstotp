import SwiftUI

struct UnlockView: View {
    @Bindable var model: AppModel
    @State private var password = ""
    @State private var loading = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            AuthHeader(subtitle: "Enter your password to unlock")

            PasswordField(title: "Password", text: $password, onSubmit: submit)
                .focused($focused)
                .disabled(loading)
                .accessibilityIdentifier("unlock.password")

            if let error = model.errorMessage {
                AuthError(message: error)
                    .accessibilityIdentifier("unlock.error")
            }

            AuthSubmitButton(title: "Unlock", busyTitle: "Unlocking…", loading: loading, action: submit)
                .disabled(loading || password.isEmpty)
                .accessibilityIdentifier("unlock.submit")
        }
        .padding(24)
        .frame(maxHeight: .infinity)
        .onAppear { focused = true }
        .onChange(of: password) { model.errorMessage = nil }
    }

    private func submit() {
        guard !loading, !password.isEmpty else { return }
        loading = true
        Task {
            let ok = await model.unlock(password: password)
            loading = false
            if ok { password = "" } else { focused = true }
        }
    }
}
