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
            ClockLogo(size: 96)
            Text("PsTotp")
                .font(.largeTitle.weight(.semibold))
                .padding(.top, 8)
            Text("Create a password to protect your vault")
                .font(.subheadline)
                .foregroundStyle(Palette.onSurfaceVariant)
                .padding(.top, 8)
                .padding(.bottom, 32)

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
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Palette.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .accessibilityIdentifier("setup.error")
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if loading { ProgressView().tint(.white) }
                    Text(loading ? "Creating vault…" : "Create Vault")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(loading || password.isEmpty)
            .padding(.top, 24)
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
