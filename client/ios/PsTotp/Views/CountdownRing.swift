import SwiftUI

/// Ring that depletes as the TOTP period runs out, wrapping `content` (the service icon).
/// Turns red in the last ~5 seconds of a 30s period.
struct CountdownRing<Content: View>: View {
    let period: Int
    var size: CGFloat = 48
    var lineWidth: CGFloat = 2.5
    @ViewBuilder var content: () -> Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let t = context.date.timeIntervalSince1970
            let fraction = period > 0 ? 1 - t.truncatingRemainder(dividingBy: Double(period)) / Double(period) : 0

            ZStack {
                Circle().stroke(Palette.surfaceVariant, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(fraction <= 0.17 ? Palette.error : Palette.primary,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: fraction)
                content()
            }
        }
        .frame(width: size, height: size)
    }
}
