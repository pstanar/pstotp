import PsTotpCore
import SwiftUI

/// Regain access after losing every device (Android's `RecoveryScreen`): redeem a recovery code, wait
/// out the server's hold period, then finish with the password. A recovery in progress is remembered,
/// so leaving the screen — or the app — doesn't lose it.
struct RecoveryView: View {
    @Bindable var model: AppModel
    let serverUrl: String
    let onFinished: () -> Void

    private enum Step: Equatable {
        case loading
        case input
        case working(String)
        case waiting(PendingRecovery)
        case ready(PendingRecovery, Envelope, String)
        case passkey(PendingRecovery)
        case codes([String])

        static func == (lhs: Step, rhs: Step) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.input, .input): true
            case (.working(let a), .working(let b)): a == b
            case (.waiting(let a), .waiting(let b)), (.passkey(let a), .passkey(let b)): a == b
            case (.ready(let a, _, _), .ready(let b, _, _)): a == b
            case (.codes(let a), .codes(let b)): a == b
            default: false
            }
        }
    }

    @State private var step = Step.loading
    @State private var email: String
    @State private var password = ""
    @State private var code = ""
    @State private var error: String?

    init(model: AppModel, serverUrl: String, email: String, onFinished: @escaping () -> Void) {
        self.model = model
        self.serverUrl = serverUrl
        self.onFinished = onFinished
        _email = State(initialValue: email)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch step {
                case .loading: ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
                case .input: inputStep
                case .working(let message): workingStep(message)
                case .waiting(let pending): waitingStep(pending)
                case .ready(let pending, let envelope, let deviceId): readyStep(pending, envelope, deviceId)
                case .passkey(let pending): passkeyStep(pending)
                case .codes(let codes): codesStep(codes)
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background)
        .navigationTitle("Account Recovery")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isLocked)
        .interactiveDismissDisabled(isLocked)
        .task { await resumeIfPending() }
    }

    /// Don't leave while the server is being changed, or before the new codes are saved.
    private var isLocked: Bool {
        switch step {
        case .working, .codes: true
        default: false
        }
    }

    // MARK: Steps

    private var inputStep: some View {
        Group {
            Text("Enter your email, password, and one of your recovery codes to regain access.")
                .font(.subheadline)
                .foregroundStyle(Palette.onSurfaceVariant)
            Text("Recovery on \(ServerURL.displayHost(ServerURL.normalize(serverUrl) ?? serverUrl))")
                .font(.footnote)
                .foregroundStyle(Palette.onSurfaceVariant)
            AuthTextField(title: "Email", text: $email, keyboard: .emailAddress)
                .accessibilityIdentifier("recovery.email")
            PasswordField(title: "Password", text: $password, submitLabel: .next)
                .accessibilityIdentifier("recovery.password")
            AuthTextField(title: "Recovery Code", text: $code, submitLabel: .done, onSubmit: start)
                .textInputAutocapitalization(.characters)
                .accessibilityIdentifier("recovery.code")
            errorLine
            AuthSubmitButton(title: "Recover Account", busyTitle: "", loading: false, action: start)
                .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty
                          || code.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("recovery.start")
        }
    }

    private func workingStep(_ message: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
            Text("This may take a moment (key derivation).")
                .font(.footnote)
                .foregroundStyle(Palette.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private func waitingStep(_ pending: PendingRecovery) -> some View {
        Group {
            Text("Recovery Hold Period").font(.title3.weight(.semibold))
            Text("For security, the server holds recovery back so the real owner has time to notice and cancel it. The recovery material will be available after:")
                .font(.footnote)
                .foregroundStyle(Palette.onSurfaceVariant)
            Text(ServerTime.dateTime(pending.releaseEarliestAt))
                .font(.body.monospaced())
                .accessibilityIdentifier("recovery.release")
            Text("You can close the app and come back: this recovery is remembered. You'll need your password to finish.")
                .font(.footnote)
                .foregroundStyle(Palette.onSurfaceVariant)

            PasswordField(title: "Password", text: $password, onSubmit: { check(pending) })
                .accessibilityIdentifier("recovery.password")
            errorLine
            AuthSubmitButton(title: "Check Again", busyTitle: "", loading: false) { check(pending) }
                .accessibilityIdentifier("recovery.check")
            forgetButton
        }
    }

    private func readyStep(_ pending: PendingRecovery, _ envelope: Envelope, _ deviceId: String) -> some View {
        Group {
            Text("Recovery Ready").font(.title3.weight(.semibold))
            Text("The hold period is over. Enter your password to finish recovering your account.")
                .font(.footnote)
                .foregroundStyle(Palette.onSurfaceVariant)
            PasswordField(title: "Password", text: $password, onSubmit: { finish(pending, envelope, deviceId) })
                .accessibilityIdentifier("recovery.password")
            errorLine
            AuthSubmitButton(title: "Finish Recovery", busyTitle: "", loading: false) { finish(pending, envelope, deviceId) }
                .disabled(password.isEmpty)
                .accessibilityIdentifier("recovery.finish")
            forgetButton
        }
    }

    private func passkeyStep(_ pending: PendingRecovery) -> some View {
        Group {
            Text("Passkey Verification Required").font(.title3.weight(.semibold))
            Text("Your account requires passkey verification to complete recovery, which this app can't do yet. Finish the recovery from the web or Android app.")
                .font(.footnote)
                .foregroundStyle(Palette.onSurfaceVariant)
                .accessibilityIdentifier("recovery.passkeyNote")
            forgetButton
        }
    }

    private func codesStep(_ codes: [String]) -> some View {
        Group {
            Text("Account Recovered").font(.title3.weight(.semibold))
            Text("Save your new recovery codes. The old codes are no longer valid.")
                .font(.footnote)
                .foregroundStyle(Palette.onSurfaceVariant)
            RecoveryCodesPanel(codes: codes) {
                model.showToast("Codes copied — clears in \(Int(Clipboard.clearAfter))s")
            }
            Text("These codes will not be shown again.")
                .font(.footnote)
                .foregroundStyle(Palette.error)
            AuthSubmitButton(title: "I've Saved My Codes", busyTitle: "", loading: false, action: onFinished)
                .accessibilityIdentifier("recovery.saved")
        }
    }

    private var forgetButton: some View {
        Button("Forget this recovery", role: .destructive) {
            Task {
                await model.forgetRecovery()
                password = ""
                error = nil
                step = .input
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityIdentifier("recovery.forget")
    }

    @ViewBuilder private var errorLine: some View {
        if let error { AuthError(message: error).accessibilityIdentifier("recovery.error") }
    }

    // MARK: Actions

    private func resumeIfPending() async {
        guard step == .loading else { return }
        if let pending = await model.pendingRecovery() {
            step = .waiting(pending)
            await advance(pending)
        } else {
            step = .input
        }
    }

    private func start() {
        guard step == .input else { return }
        error = nil
        step = .working("Verifying credentials and recovery code…")
        Task {
            switch await model.startRecovery(serverUrl: serverUrl, email: email, password: password, code: code) {
            case .success(let pending):
                code = ""
                await advance(pending)
            case .failure(let failure):
                error = failure.message
                step = .input
            }
        }
    }

    private func check(_ pending: PendingRecovery) {
        error = nil
        step = .working("Checking…")
        Task { await advance(pending) }
    }

    /// Asks the server where the recovery stands and shows the matching step.
    private func advance(_ pending: PendingRecovery) async {
        switch await model.checkRecovery(pending) {
        case .waiting(let updated): step = .waiting(updated)
        case .needsPasskey(let pending): step = .passkey(pending)
        case .ready(let pending, let envelope, let deviceId):
            if password.isEmpty {
                step = .ready(pending, envelope, deviceId)
            } else {
                finish(pending, envelope, deviceId)
            }
        case .failed(let message):
            error = message
            // A forgotten session means starting over; anything else can be retried.
            step = (await model.pendingRecovery()) == nil ? .input : .waiting(pending)
        }
    }

    private func finish(_ pending: PendingRecovery, _ envelope: Envelope, _ deviceId: String) {
        error = nil
        step = .working("Recovering account…")
        Task {
            switch await model.completeRecovery(pending, password: password, envelope: envelope, replacementDeviceId: deviceId) {
            case .success(let codes):
                password = ""
                step = .codes(codes)
            case .failure(let failure):
                error = failure.message
                step = (await model.pendingRecovery()) == nil ? .input : .ready(pending, envelope, deviceId)
            }
        }
    }
}
