import SwiftUI

/// Logo, app name and a one-line prompt: the top of the setup and unlock screens.
struct AuthHeader: View {
    let subtitle: String

    var body: some View {
        ClockLogo(size: 96)
        Text("PsTotp")
            .font(.largeTitle.weight(.semibold))
            .padding(.top, 8)
        Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(Palette.onSurfaceVariant)
            .padding(.top, 8)
            .padding(.bottom, 32)
    }
}

/// The error line under the password field(s).
struct AuthError: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(Palette.error)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

/// Full-width primary button that shows a spinner and `busyTitle` while `loading`.
struct AuthSubmitButton: View {
    let title: String
    let busyTitle: String
    let loading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading { ProgressView().tint(.white) }
                Text(loading ? busyTitle : title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.top, 24)
    }
}
