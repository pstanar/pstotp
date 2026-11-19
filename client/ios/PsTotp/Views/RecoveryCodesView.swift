import PsTotpCore
import SwiftUI

/// Replace the account's recovery codes (Android's `RegenerateCodesScreen`). Connected only.
struct RecoveryCodesView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum Step { case confirm, working, codes }

    @State private var step = Step.confirm
    @State private var password = ""
    @State private var codes: [String] = []
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch step {
                case .confirm: confirmStep
                case .working: workingStep
                case .codes: codesStep
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background)
        .navigationTitle("Recovery Codes")
        .navigationBarTitleDisplayMode(.inline)
        // Once the server has new codes, the old ones are gone: don't let a swipe discard the new ones.
        .navigationBarBackButtonHidden(step != .confirm)
        .interactiveDismissDisabled(step != .confirm)
    }

    private var confirmStep: some View {
        Group {
            Text("Regenerate Recovery Codes").font(.title3.weight(.semibold))
            Text("This will invalidate all existing recovery codes and generate \(RecoveryCodes.count) new ones. Make sure you save the new codes.")
                .font(.footnote)
                .foregroundStyle(Palette.onSurfaceVariant)

            PasswordField(title: "Password", text: $password, onSubmit: regenerate)
                .accessibilityIdentifier("recovery.password")
            if let error { AuthError(message: error).accessibilityIdentifier("recovery.error") }

            AuthSubmitButton(title: "Regenerate Codes", action: regenerate)
                .disabled(password.isEmpty)
                .accessibilityIdentifier("recovery.regenerate")
            Button("Cancel") { dismiss() }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    private var workingStep: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Generating new recovery codes…")
            Text("This may take a moment (key derivation).")
                .font(.footnote)
                .foregroundStyle(Palette.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private var codesStep: some View {
        Group {
            Text("New Recovery Codes").font(.title3.weight(.semibold))
            Text("Your old codes are no longer valid. Save these new codes in a safe place.")
                .font(.footnote)
                .foregroundStyle(Palette.onSurfaceVariant)
            RecoveryCodesPanel(codes: codes) {
                model.showToast("Codes copied — clears in \(Int(Clipboard.clearAfter))s")
            }
            Text("These codes will not be shown again.")
                .font(.footnote)
                .foregroundStyle(Palette.error)
            AuthSubmitButton(title: "I've Saved My Codes") {
                codes = []
                dismiss()
            }
            .accessibilityIdentifier("recovery.saved")
        }
    }

    private func regenerate() {
        guard step == .confirm, !password.isEmpty else { return }
        error = nil
        step = .working
        Task {
            switch await model.regenerateRecoveryCodes(password: password) {
            case .success(let newCodes):
                codes = newCodes
                password = ""
                step = .codes
            case .failure(let failure):
                error = failure.message
                step = .confirm
            }
        }
    }
}
