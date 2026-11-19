import SwiftUI

/// The numbered recovery codes with Copy and Share (shown after registering and after regenerating).
struct RecoveryCodesPanel: View {
    let codes: [String]
    let onCopied: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(codes.enumerated()), id: \.offset) { index, code in
                    Text("\(index + 1). \(code)")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 8)
            .accessibilityIdentifier("recovery.codes")

            HStack {
                Button("Copy") {
                    Clipboard.copy(codes.joined(separator: "\n"))
                    onCopied()
                }
                .buttonStyle(.bordered)
                ShareLink(item: codes.joined(separator: "\n"), subject: Text("PsTotp recovery codes"))
                    .buttonStyle(.bordered)
            }
        }
    }
}
