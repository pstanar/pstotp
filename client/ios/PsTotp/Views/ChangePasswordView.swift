import PsTotpCore
import SwiftUI

/// Change the account password (Android's `ChangePasswordScreen`). Connected only.
struct ChangePasswordView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case current, new, confirm }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Changes the password on both this device and the server. Other devices will need to sign in again.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)

                PasswordField(title: "Current Password", text: $current, submitLabel: .next) { focus = .new }
                    .focused($focus, equals: .current)
                    .accessibilityIdentifier("changePassword.current")
                PasswordField(title: "New Password", text: $new, submitLabel: .next) { focus = .confirm }
                    .focused($focus, equals: .new)
                    .accessibilityIdentifier("changePassword.new")
                PasswordField(title: "Confirm New Password", text: $confirm, onSubmit: submit)
                    .focused($focus, equals: .confirm)
                    .accessibilityIdentifier("changePassword.confirm")

                if let error {
                    AuthError(message: error).accessibilityIdentifier("changePassword.error")
                }

                AuthSubmitButton(title: "Change Password", busyTitle: "Changing…", loading: busy, action: submit)
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("changePassword.submit")
            }
            .disabled(busy)
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background)
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(busy)   // the server has changed by the time it returns: don't leave mid-way
        .onChange(of: current) { error = nil }
        .onChange(of: new) { error = nil }
        .onChange(of: confirm) { error = nil }
    }

    private var canSubmit: Bool { !busy && !current.isEmpty && !new.isEmpty && !confirm.isEmpty }

    private func submit() {
        guard canSubmit else { return }
        busy = true
        error = nil
        Task {
            if let problem = await model.changePassword(current: current, new: new, confirm: confirm) {
                error = problem
            } else {
                dismiss()
            }
            busy = false
        }
    }
}
