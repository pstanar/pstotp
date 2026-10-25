import SwiftUI

struct UnlockView: View {
    @Bindable var model: AppModel
    @State private var password = ""
    @State private var loading = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ClockLogo(size: 96)
            Text("PsTotp")
                .font(.largeTitle.weight(.semibold))
                .padding(.top, 8)
            Text("Enter your password to unlock")
                .font(.subheadline)
                .foregroundStyle(Palette.onSurfaceVariant)
                .padding(.top, 8)
                .padding(.bottom, 32)

            PasswordField(title: "Password", text: $password, onSubmit: submit)
                .focused($focused)
                .disabled(loading)
                .accessibilityIdentifier("unlock.password")

            if let error = model.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Palette.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .accessibilityIdentifier("unlock.error")
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if loading { ProgressView().tint(.white) }
                    Text(loading ? "Unlocking…" : "Unlock")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(loading || password.isEmpty)
            .padding(.top, 24)
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
