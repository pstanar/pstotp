import SwiftUI

/// A password field with a show/hide toggle (Android's `PasswordField`).
struct PasswordField: View {
    let title: String
    @Binding var text: String
    var submitLabel: SubmitLabel = .done
    var onSubmit: () -> Void = {}

    @State private var revealed = false

    var body: some View {
        HStack {
            Group {
                if revealed {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)

            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .foregroundStyle(Palette.onSurfaceVariant)
            }
            .accessibilityLabel(revealed ? "Hide password" : "Show password")
        }
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.outline, lineWidth: 1))
    }
}
