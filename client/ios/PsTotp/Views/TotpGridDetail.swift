import PsTotpCore
import SwiftUI

/// Authy-style detail panel for the grid layout: big icon in a countdown ring, issuer and account,
/// the code large and monospaced, and a "token expires in Ns" line with a copy button.
/// The whole panel is tappable (not just the button), like the list rows.
struct TotpGridDetail: View {
    let entry: VaultEntry
    let onCopy: (String) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = Int64(context.date.timeIntervalSince1970)
            let code = entry.code(at: now)
            let timeLeft = TotpGenerator.timeRemaining(period: entry.period, now: now)

            VStack(spacing: 0) {
                CountdownRing(period: entry.period, size: 72, lineWidth: 3) {
                    ServiceIconView(issuer: entry.issuer, icon: entry.icon, size: 52)
                }

                Text(entry.issuer)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .padding(.top, 10)
                    .accessibilityIdentifier("grid.issuer")
                if !entry.accountName.isEmpty, entry.accountName != entry.issuer {
                    Text(entry.accountName)
                        .font(.subheadline)
                        .foregroundStyle(Palette.onSurfaceVariant)
                        .lineLimit(1)
                }

                CodeText(code: code, size: 44)
                    .contentTransition(.opacity)
                    .accessibilityIdentifier("grid.code")
                    .padding(.top, 16)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

                HStack {
                    Color.clear.frame(width: 40, height: 1)          // balances the copy button
                    Text("Your token expires in \(timeLeft)s")
                        .font(.footnote)
                        .foregroundStyle(timeLeft <= 5 ? Palette.error : Palette.onSurfaceVariant)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                    Button {
                        if let code { onCopy(code) }
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 40, height: 40)
                    }
                    .disabled(code == nil)
                    .accessibilityLabel("Copy code")
                    .accessibilityIdentifier("grid.copy")
                }
                .padding(.top, 6)
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { if let code { onCopy(code) } }
            .accessibilityElement(children: .contain)
        }
        .accessibilityIdentifier("grid.detail")
    }
}
