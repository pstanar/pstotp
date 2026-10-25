import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var screenCapture = ScreenCaptureMonitor()

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            switch model.phase {
            case .loading:
                ProgressView()
            case .needsSetup:
                SetupView(model: model)
            case .locked:
                UnlockView(model: model)
            case .unlocked:
                VaultView(model: model)
            }

            // iOS can't block screenshots (Android's FLAG_SECURE), but it can keep codes out of the
            // app-switcher snapshot and off a screen recording / mirrored display.
            if scenePhase != .active || screenCapture.isCaptured {
                PrivacyCover()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.phase)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(text: toast)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: model.toast)
        .tint(Palette.primary)
        .foregroundStyle(Palette.onBackground)
        .task { await model.start() }
        .onChange(of: scenePhase) { _, newPhase in model.scenePhaseChanged(newPhase) }
    }
}

private struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ClockLogo(size: 96)
        }
        .accessibilityHidden(true)
    }
}

private struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Palette.outline, lineWidth: 0.5))
            .accessibilityIdentifier("toast")
    }
}

/// Tracks whether the screen is being recorded or mirrored.
@MainActor
@Observable
final class ScreenCaptureMonitor {
    private(set) var isCaptured = false
    private var observer: NSObjectProtocol?

    init() {
        isCaptured = Self.currentlyCaptured()
        observer = NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isCaptured = Self.currentlyCaptured() }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private static func currentlyCaptured() -> Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { $0.screen.isCaptured }
    }
}
