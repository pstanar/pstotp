import SwiftUI

struct UnlockView: View {
    @Bindable var model: AppModel
    @State private var password = ""
    @State private var loading = false
    @State private var prompting = false
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

            if model.canUnlockWithBiometrics, let biometry = model.biometry {
                Button {
                    promptBiometrics()
                } label: {
                    Label("Unlock with \(biometry.name)", systemImage: biometry.systemImage)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.top, 16)
                .disabled(loading || prompting)
                .accessibilityIdentifier("unlock.biometric")
            }
        }
        .padding(24)
        .frame(maxHeight: .infinity)
        .onAppear {
            // As on Android, offer the prompt straight away when it's turned on; the keyboard
            // would only sit behind it.
            if model.canUnlockWithBiometrics { promptBiometrics() } else { focused = true }
        }
        .onChange(of: password) { model.errorMessage = nil }
    }

    private func promptBiometrics() {
        guard !prompting else { return }
        prompting = true
        Task {
            let ok = await model.unlockWithBiometrics()
            prompting = false
            if !ok { focused = true }
        }
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
