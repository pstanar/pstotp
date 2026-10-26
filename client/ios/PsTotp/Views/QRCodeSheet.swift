import PsTotpCore
import SwiftUI

/// Shows an entry's `otpauth://` QR code so another authenticator can scan it.
struct QRCodeSheet: View {
    let entry: VaultEntry
    @Environment(\.dismiss) private var dismiss

    private var uri: String {
        OtpauthUri.build(VaultEntryPlaintext(
            issuer: entry.issuer, accountName: entry.accountName, secret: entry.secret,
            algorithm: entry.algorithm, digits: entry.digits, period: entry.period, icon: entry.icon))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let image = QRCode.render(uri, size: 768) {
                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 256, height: 256)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("QR code for \(entry.issuer)")
                        .accessibilityIdentifier("qr.image")
                } else {
                    Text("Failed to generate QR code")
                        .foregroundStyle(Palette.error)
                        .accessibilityIdentifier("qr.failed")
                }

                Text("Scan this with another authenticator to copy the account. Anyone who can see this code can generate your codes — keep it private.")
                    .font(.footnote)
                    .foregroundStyle(Palette.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
            .navigationTitle(entry.accountName.isEmpty ? entry.issuer : "\(entry.issuer) — \(entry.accountName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
