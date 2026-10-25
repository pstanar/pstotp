import SwiftUI

@main
struct PsTotpApp: App {
    private let startup: Result<AppModel, Error>

    init() {
        startup = Result { try AppModel.bootstrap() }
    }

    var body: some Scene {
        WindowGroup {
            switch startup {
            case .success(let model):
                RootView(model: model)
            case .failure(let error):
                StartupFailureView(message: error.localizedDescription)
            }
        }
    }
}

/// Shown if the database can't be opened. Nothing is deleted or reset automatically: the vault file
/// is the user's only copy of their (encrypted) secrets.
struct StartupFailureView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Palette.error)
            Text("PsTotp couldn't open its vault")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Palette.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}
