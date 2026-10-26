import PsTotpCore
import SwiftUI

/// One vault row: service icon in a countdown ring, issuer, account, and the live code.
/// Tapping anywhere copies the code (Authy-style), like the Android card.
struct TotpCard: View {
    let entry: VaultEntry
    let onCopyCode: (String) -> Void
    let onCopySecret: () -> Void
    let onShowQR: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = Int64(context.date.timeIntervalSince1970)
            let code = try? TotpGenerator.generate(
                secret: entry.secret, algorithm: entry.algorithm, digits: entry.digits,
                period: entry.period, timestampSeconds: now)
            let timeLeft = TotpGenerator.timeRemaining(period: entry.period, now: now)

            HStack(spacing: 12) {
                CountdownRing(period: entry.period, size: 48) {
                    ServiceIconView(issuer: entry.issuer, icon: entry.icon, size: 36)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.issuer)
                        .font(.title3)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .lineLimit(1)
                    if !entry.accountName.isEmpty {
                        Text(entry.accountName)
                            .font(.caption)
                            .foregroundStyle(Palette.onSurfaceVariant.opacity(0.8))
                            .lineLimit(1)
                    }
                    HStack(spacing: 12) {
                        if let code {
                            Text(CodeFormat.grouped(code))
                                .font(.system(size: 28, weight: .bold, design: .monospaced))
                                .tracking(2)
                                .accessibilityIdentifier("code")
                                .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
                        } else {
                            Label("Invalid secret", systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                                .foregroundStyle(Palette.error)
                        }
                        if code != nil, timeLeft <= 10 {
                            Text("\(timeLeft)s")
                                .font(.footnote)
                                .foregroundStyle(timeLeft <= 5 ? Palette.error : Palette.onSurfaceVariant)
                                .monospacedDigit()
                        }
                    }
                }

                Spacer(minLength: 0)

                Menu {
                    Button("Copy Secret Key", systemImage: "key", action: onCopySecret)
                    Button("Show QR Code", systemImage: "qrcode", action: onShowQR)
                    Button("Edit", systemImage: "pencil", action: onEdit)
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 44)
                        .foregroundStyle(Palette.onSurfaceVariant)
                }
                .accessibilityLabel("More options for \(entry.issuer)")
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture { if let code { onCopyCode(code) } }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Copy code") { if let code { onCopyCode(code) } }
        }
        .accessibilityIdentifier("card.\(entry.issuer)")
    }
}
