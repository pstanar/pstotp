import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PsTotpCore

@Suite("QR codes")
struct QRTests {

    private let uri = "otpauth://totp/octocat?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA1&digits=6&period=30"

    private func png(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        precondition(CGImageDestinationFinalize(dest))
        return data as Data
    }

    // MARK: Generate + decode

    @Test func renderedCodeDecodesBackToTheSameText() throws {
        let image = try #require(QRCode.render(uri))
        #expect(QRCode.decode(image) == [uri])
    }

    @Test(arguments: [
        "otpauth://totp/Bank%2FCorp%20%26%20Co:bob%3A%20work?secret=NBSWY3DPFQQHO33SNRSCC&issuer=Bank%2FCorp&digits=8&period=60",
        "otpauth://totp/日本語%20🔑:ünïcode?secret=JBSWY3DPEHPK3PXP&issuer=%E6%97%A5%E6%9C%AC%E8%AA%9E",
        "a",
        String(repeating: "otpauth://x?secret=ABCDEFGH&", count: 20),     // ~560 bytes → a dense, high-version code
    ])
    func roundTripsAwkwardPayloads(text: String) throws {
        let image = try #require(QRCode.render(text, size: 1024))
        #expect(QRCode.decode(image) == [text])
    }

    /// CoreImage must stand on its own: it is the only detector that works in the iOS Simulator.
    @Test func coreImageDetectorAloneDecodesRenderedCodes() throws {
        for text in [uri, "a", "日本語 🔑 otpauth://x?secret=ABCDEFGH"] {
            let image = try #require(QRCode.render(text, size: 768))
            #expect(QRCode.decodeWithCoreImage(image) == [text])
        }
    }

    @Test func renderIsOpaqueSquareAndNeverLargerThanRequested() throws {
        for size in [128, 256, 512] {
            let image = try #require(QRCode.render(uri, size: size))
            #expect(image.width == image.height)
            #expect(image.width <= size)
            #expect(image.width > size / 2)                                  // uses most of the space
            #expect(image.alphaInfo == .noneSkipLast || image.alphaInfo == .noneSkipFirst)
        }
    }

    @Test func quietZoneIsWhiteOnAllSides() throws {
        let image = try #require(QRCode.render(uri, size: 512))
        let data = try #require(image.dataProvider?.data as Data?)
        let bytesPerRow = image.bytesPerRow
        let bpp = image.bitsPerPixel / 8
        func pixel(_ x: Int, _ y: Int) -> [UInt8] { Array(data[(y * bytesPerRow + x * bpp)..<(y * bytesPerRow + x * bpp + 3)]) }
        let last = image.width - 1
        for (x, y) in [(0, 0), (last, 0), (0, last), (last, last), (last / 2, 0), (0, last / 2)] {
            #expect(pixel(x, y) == [255, 255, 255], "pixel (\(x),\(y)) not white")
        }
    }

    @Test func imageWithoutAQRCodeDecodesToNothing() throws {
        let ctx = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        #expect(QRCode.decode(ctx.makeImage()!) == [])
    }

    @Test func decodesEveryCodeInAnImage() throws {
        let a = try #require(QRCode.render("first", size: 300))
        let b = try #require(QRCode.render("second", size: 300))
        let ctx = CGContext(data: nil, width: a.width + b.width, height: max(a.height, b.height), bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(a, in: CGRect(x: 0, y: 0, width: a.width, height: a.height))
        ctx.draw(b, in: CGRect(x: a.width, y: 0, width: b.width, height: b.height))
        #expect(Set(QRCode.decode(ctx.makeImage()!)) == ["first", "second"])
    }

    // MARK: Image bytes

    @Test func imageDataDecodingReadsPNG() throws {
        let rendered = try #require(QRCode.render(uri))
        let image = try #require(QRCode.image(from: png(rendered)))
        #expect(QRCode.decode(image) == [uri])
    }

    @Test func nonImageDataIsNotAnImage() {
        #expect(QRCode.image(from: Data("not an image".utf8)) == nil)
        #expect(QRCode.image(from: Data()) == nil)
    }

    @Test func hugeImagesAreBoundedWhenDecoded() throws {
        let big = try #require(QRCode.render(uri, size: 2000))
        let image = try #require(QRCode.image(from: png(big), maxPixelSize: 600))
        #expect(max(image.width, image.height) <= 600)
        #expect(QRCode.decode(image) == [uri])                                // still readable when scaled down
    }

    // MARK: QRImport

    @Test func importPicksTheOtpauthCodeAmongOthers() throws {
        let entry = try QRImport.entry(fromCodes: ["https://example.com", uri, "otpauth://totp/other?secret=JBSW"])
        #expect(entry == VaultEntryPlaintext(issuer: "GitHub", accountName: "octocat", secret: "JBSWY3DPEHPK3PXP"))
    }

    @Test func importRejectsCodesThatAreNotAuthenticatorAccounts() {
        #expect(throws: QRImport.Failure.noQRCode) { try QRImport.entry(fromCodes: []) }
        #expect(throws: QRImport.Failure.noQRCode) { try QRImport.entry(fromCodes: ["https://example.com"]) }
        // Google's migration QR is deliberately not scanned (same as Android).
        #expect(throws: QRImport.Failure.noQRCode) {
            try QRImport.entry(fromCodes: ["otpauth-migration://offline?data=abc"])
        }
    }

    @Test func importSurfacesParseAndValidationErrors() {
        #expect(throws: OtpauthError.unsupportedType) {
            try QRImport.entry(fromCodes: ["otpauth://hotp/a?secret=JBSWY3DPEHPK3PXP&counter=1"])
        }
        #expect(throws: EntryValidationError.secretInvalid) {
            try QRImport.entry(fromCodes: ["otpauth://totp/a?secret=!!!!"])
        }
    }

    @Test func importFromImageDataEndToEnd() throws {
        let data = png(try #require(QRCode.render(uri)))
        #expect(try QRImport.entry(fromImageData: data).issuer == "GitHub")
        #expect(throws: QRImport.Failure.unreadableImage) { try QRImport.entry(fromImageData: Data([1, 2, 3])) }
    }

    @Test func importFromAnImageWithNoQRSaysSo() throws {
        let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        #expect(throws: QRImport.Failure.noQRCode) { try QRImport.entry(fromImageData: png(ctx.makeImage()!)) }
    }

    @Test func failureMessagesMatchAndroid() {
        #expect(QRImport.Failure.unreadableImage.description == "Failed to load image")
        #expect(QRImport.Failure.noQRCode.description == "No QR code found in image")
    }

    // MARK: Debounce

    @Test func debouncerSuppressesRepeatsWithinTheInterval() {
        var d = ScanDebouncer(interval: 2)
        let t0 = Date(timeIntervalSince1970: 1_000)
        // (value, seconds since t0, should be handled) — evaluated outside #expect (it mutates).
        let steps: [(String, Double, Bool)] = [
            ("a", 0, true), ("a", 0.1, false), ("a", 1.9, false),
            ("a", 2.1, true),                       // retried after a pause
            ("b", 2.2, true),                       // a different code is immediate
            ("a", 2.3, true),
        ]
        for (value, offset, expected) in steps {
            let handled = d.shouldHandle(value, at: t0.addingTimeInterval(offset))
            #expect(handled == expected, "\(value) at +\(offset)s")
        }
    }
}
