import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import Vision

/// QR code generation and detection (the ZXing writer + ML Kit scanner on Android), built on
/// CoreImage and Vision so it works identically on iOS and on the host for tests.
public enum QRCode {

    /// Render `text` as a crisp, opaque QR image with a 4-module quiet zone.
    ///
    /// The image is the largest whole-pixel-per-module rendering that fits in `size` points, so it
    /// never exceeds `size` and never needs smoothing; display it with `.interpolation(.none)`.
    public static func render(_ text: String, size: Int = 512) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let modules = Int(output.extent.width)
        guard modules > 0, let matrix = CIContext().createCGImage(output, from: output.extent) else { return nil }

        let quiet = 4
        let scale = max(1, size / (modules + 2 * quiet))
        let pixels = (modules + 2 * quiet) * scale
        guard let ctx = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        ctx.interpolationQuality = .none
        ctx.draw(matrix, in: CGRect(x: quiet * scale, y: quiet * scale,
                                    width: modules * scale, height: modules * scale))
        return ctx.makeImage()
    }

    /// Payload strings of every QR code found in `image`, in detection order.
    ///
    /// Vision is tried first (best with skewed or low-contrast photos on a device). Its barcode
    /// detector returns nothing in the iOS Simulator, and can also miss a clean code, so when it
    /// finds nothing CoreImage's CPU-only QR detector gets a turn.
    public static func decode(_ image: CGImage) -> [String] {
        let viaVision = decodeWithVision(image)
        return viaVision.isEmpty ? decodeWithCoreImage(image) : viaVision
    }

    static func decodeWithVision(_ image: CGImage) -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }

    static func decodeWithCoreImage(_ image: CGImage) -> [String] {
        guard let detector = CIDetector(
            ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        else { return [] }
        return detector.features(in: CIImage(cgImage: image))
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }

    /// Decode encoded image bytes (PNG, JPEG, HEIC, …), honouring EXIF orientation and bounding
    /// the decoded size so a huge photo can't exhaust memory. Nil when the data isn't an image.
    public static func image(from data: Data, maxPixelSize: Int = 4096) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
