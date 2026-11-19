import PsTotpCore
import SwiftUI

/// Create an account on the server (Android's `RegisterScreen`): email → verification code →
/// password → recovery codes.
struct RegisterView: View {
    @Bindable var model: AppModel
    let serverUrl: String
    let onFinished: () -> Void

    private enum Step { case email, verify, password, working, codes }

    @State private var step = Step.email
    @State private var email: String
    @State private var code = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var sessionId: String?
    @State private var recoveryCodes: [String] = []
    @State private var busy = false
    @State private var error: String?

    init(model: AppModel, serverUrl: String, initialEmail: String, onFinished: @escaping () -> Void) {
        self.model = model
        self.serverUrl = serverUrl
        self.onFinished = onFinished
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Register on \(ServerURL.displayHost(ServerURL.normalize(serverUrl) ?? serverUrl))")
                    .font(.subheadline)
                    .foregroundStyle(Palette.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)

                switch step {
                case .email: emailStep
                case .verify: verifyStep
                case .password: passwordStep
                case .working: workingStep
                case .codes: codesStep
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background)
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
        // The codes are shown once: don't let a back swipe throw them away.
        .navigationBarBackButtonHidden(step == .codes || step == .working)
        .interactiveDismissDisabled(step == .codes || step == .working)
    }

    // MARK: Steps

    private var emailStep: some View {
        Group {
            AuthTextField(title: "Email", text: $email, keyboard: .emailAddress, submitLabel: .done, onSubmit: begin)
                .accessibilityIdentifier("register.email")
            errorLine
            AuthSubmitButton(title: "Continue", busyTitle: "Continuing…", loading: busy, action: begin)
                .disabled(busy || email.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("register.continue")
        }
    }

    private var verifyStep: some View {
        Group {
            Text("Enter the verification code sent to \(email)")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            AuthTextField(title: "Verification Code", text: $code, keyboard: .numbersAndPunctuation, submitLabel: .done, onSubmit: verify)
                .accessibilityIdentifier("register.code")
            errorLine
            AuthSubmitButton(title: "Verify", busyTitle: "Verifying…", loading: busy, action: verify)
                .disabled(busy || code.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("register.verify")
        }
    }

    private var passwordStep: some View {
        Group {
            PasswordField(title: "Password", text: $password, submitLabel: .next)
                .accessibilityIdentifier("register.password")
            PasswordField(title: "Confirm Password", text: $confirm, onSubmit: create)
                .accessibilityIdentifier("register.confirm")
            errorLine
            AuthSubmitButton(title: "Create Account", busyTitle: "Creating…", loading: false, action: create)
                .disabled(password.isEmpty || confirm.isEmpty)
                .accessibilityIdentifier("register.create")
        }
    }

    private var workingStep: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Creating account…")
            Text("This may take a moment (key derivation).")
                .font(.footnote)
                .foregroundStyle(Palette.onSurfaceVariant)
        }
        .padding(.top, 24)
    }

    private var codesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Your Recovery Codes").font(.title3.weight(.semibold))
            Text("Store these codes in a safe place. They are the only way to recover your account if you lose all your devices.")
                .font(.footnote)
                .foregroundStyle(Palette.onSurfaceVariant)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(recoveryCodes.enumerated()), id: \.offset) { index, code in
                    Text("\(index + 1). \(code)")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 8)
            .accessibilityIdentifier("register.codes")

            HStack {
                Button("Copy") {
                    Clipboard.copy(recoveryCodes.joined(separator: "\n"))
                    model.showToast("Codes copied — clears in \(Int(Clipboard.clearAfter))s")
                }
                .buttonStyle(.bordered)
                ShareLink(item: recoveryCodes.joined(separator: "\n"), subject: Text("PsTotp recovery codes"))
                    .buttonStyle(.bordered)
            }
            AuthSubmitButton(title: "I've Saved My Codes", busyTitle: "", loading: false, action: onFinished)
                .accessibilityIdentifier("register.saved")
        }
    }

    @ViewBuilder private var errorLine: some View {
        if let error { AuthError(message: error).accessibilityIdentifier("register.error") }
    }

    // MARK: Actions

    private func begin() {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            switch await model.beginRegistration(serverUrl: serverUrl, email: email) {
            case .started(let id, let needsEmailCode, let devCode):
                sessionId = id
                if needsEmailCode {
                    if let devCode { code = devCode }
                    step = .verify
                } else {
                    step = .password
                }
            case .failed(let message):
                error = message
            }
            busy = false
        }
    }

    private func verify() {
        guard !busy, let sessionId else { return }
        busy = true
        error = nil
        Task {
            if let problem = await model.verifyEmail(sessionId: sessionId, code: code) {
                error = problem
            } else {
                step = .password
            }
            busy = false
        }
    }

    private func create() {
        guard step == .password else { return }
        if password != confirm { error = "Passwords do not match"; return }
        if password.count < 8 { error = "Password must be at least 8 characters"; return }
        error = nil
        step = .working
        Task {
            switch await model.register(serverUrl: serverUrl, email: email, password: password, sessionId: sessionId) {
            case .success(let codes):
                recoveryCodes = codes
                password = ""
                confirm = ""
                step = .codes
            case .failure(let failure):
                error = failure.message
                step = .password
            }
        }
    }
}
