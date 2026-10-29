import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Normalises icons to the 64×64 PNG data URL every client stores. The counterpart of Android's
/// `IconFetch.resizeBytesToDataUrl`: scale to cover, centre-crop, re-encode as PNG.
public enum IconNormalizer {
    public static let size = 64

    public static func isUrl(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.hasPrefix("http://") || value.hasPrefix("https://")
    }

    /// The raw bytes carried by a `data:` URL (base64 or percent-encoded); nil for anything else.
    public static func dataUrlBytes(_ dataUrl: String) -> Data? {
        guard dataUrl.hasPrefix("data:"), let comma = dataUrl.firstIndex(of: ",") else { return nil }
        let meta = dataUrl[dataUrl.index(dataUrl.startIndex, offsetBy: 5)..<comma]
        let payload = String(dataUrl[dataUrl.index(after: comma)...])
        if meta.contains(";base64") {
            return Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
        }
        return payload.removingPercentEncoding.map { Data($0.utf8) }
    }

    /// Decode any bitmap format ImageIO knows and re-encode it as a centred 64×64 PNG data URL.
    /// Nil when the bytes aren't a decodable bitmap (SVG included, as on Android).
    public static func normalizedDataUrl(imageBytes: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(imageBytes as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0, image.height > 0
        else { return nil }

        let side = CGFloat(size)
        let scale = max(side / CGFloat(image.width), side / CGFloat(image.height))
        let scaledWidth = CGFloat(image.width) * scale
        let scaledHeight = CGFloat(image.height) * scale

        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(
            x: (side - scaledWidth) / 2, y: (side - scaledHeight) / 2,
            width: scaledWidth, height: scaledHeight))

        guard let resized = context.makeImage() else { return nil }
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, resized, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return "data:image/png;base64,\((png as Data).base64EncodedString())"
    }
}
