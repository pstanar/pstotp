import SwiftUI

/// The PsTotp clock-face logo with live hour / minute hands and the key as the second hand.
/// Geometry is the Android vector drawables (`ic_login_*.xml`) on a 512×512 viewport.
struct ClockLogo: View {
    var size: CGFloat = 96
    /// Fixed time for previews and tests; nil follows the wall clock.
    var date: Date?

    private static let ink = Color(argb: 0xFF4A3728)
    private static let face = Color(argb: 0xFFF0EBE5)
    private static let keyColor = Color(argb: 0xFFB45309)

    var body: some View {
        Group {
            if let date {
                clock(at: date)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { clock(at: $0.date) }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("PsTotp")
    }

    private func clock(at date: Date) -> some View {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let (h, m, s) = (Double(c.hour ?? 0), Double(c.minute ?? 0), Double(c.second ?? 0))
        let hourAngle = (h.truncatingRemainder(dividingBy: 12)) * 30 + m * 0.5
        let minuteAngle = m * 6 + s * 0.1
        // The key is drawn pointing at 4:30; -135° makes second 0 point straight up.
        let secondAngle = s * 6 - 135

        return Canvas { ctx, canvas in
            let scale = canvas.width / 512
            var ctx = ctx
            ctx.scaleBy(x: scale, y: scale)

            // Face
            let faceRect = CGRect(x: 16, y: 16, width: 480, height: 480)
            ctx.fill(Path(ellipseIn: faceRect), with: .color(Self.face))
            ctx.stroke(Path(ellipseIn: faceRect), with: .color(Self.ink), lineWidth: 24)

            // Hour ticks
            for (a, b) in Self.ticks {
                line(&ctx, a, b, width: 8, color: Self.ink)
            }

            // Hands, rotated about the dial centre
            rotated(ctx, degrees: hourAngle) { line(&$0, CGPoint(x: 256, y: 256), CGPoint(x: 256, y: 128), width: 14, color: Self.ink) }
            rotated(ctx, degrees: minuteAngle) { line(&$0, CGPoint(x: 256, y: 256), CGPoint(x: 256, y: 106), width: 10, color: Self.ink) }
            ctx.fill(Path(ellipseIn: CGRect(x: 244, y: 244, width: 24, height: 24)), with: .color(Self.ink))

            // Key
            rotated(ctx, degrees: secondAngle) { k in
                k.stroke(Path(ellipseIn: CGRect(x: 208, y: 208, width: 96, height: 96)),
                         with: .color(Self.keyColor), lineWidth: 16)
                line(&k, CGPoint(x: 289.94, y: 289.94), CGPoint(x: 383.28, y: 383.28), width: 14, color: Self.keyColor)
                line(&k, CGPoint(x: 354.99, y: 354.99), CGPoint(x: 336.61, y: 373.38), width: 12, color: Self.keyColor)
                line(&k, CGPoint(x: 372.67, y: 372.67), CGPoint(x: 358.53, y: 386.81), width: 12, color: Self.keyColor)
            }
        }
    }

    private func line(_ ctx: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, width: CGFloat, color: Color) {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func rotated(_ ctx: GraphicsContext, degrees: Double, draw: (inout GraphicsContext) -> Void) {
        var copy = ctx
        copy.translateBy(x: 256, y: 256)
        copy.rotate(by: .degrees(degrees))
        copy.translateBy(x: -256, y: -256)
        draw(&copy)
    }

    private static let ticks: [(CGPoint, CGPoint)] = [
        ((256, 40), (256, 72)), ((364, 76), (348, 104)), ((436, 148), (408, 164)), ((472, 256), (440, 256)),
        ((436, 364), (408, 348)), ((364, 436), (348, 408)), ((256, 472), (256, 440)), ((148, 436), (164, 408)),
        ((76, 364), (104, 348)), ((40, 256), (72, 256)), ((76, 148), (104, 164)), ((148, 76), (164, 104)),
    ].map { (CGPoint(x: $0.0.0, y: $0.0.1), CGPoint(x: $0.1.0, y: $0.1.1)) }
}

#Preview { ClockLogo(size: 192, date: Date(timeIntervalSince1970: 1_700_000_000)).padding() }
