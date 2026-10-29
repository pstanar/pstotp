import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PsTotpCore

@Suite("Icon normalisation")
struct IconNormalizerTests {
    /// A solid-colour PNG of the given size.
    static func png(width: Int, height: Int, type: UTType = .png) -> Data {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    private func decodedSize(_ dataUrl: String) throws -> (Int, Int) {
        let bytes = try #require(IconNormalizer.dataUrlBytes(dataUrl))
        let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    @Test func anyBitmapBecomesA64PxPng() throws {
        for (w, h, type) in [(200, 100, UTType.png), (16, 16, .png), (300, 500, .jpeg)] {
            let url = try #require(IconNormalizer.normalizedDataUrl(imageBytes: Self.png(width: w, height: h, type: type)))
            #expect(url.hasPrefix("data:image/png;base64,"))
            let size = try decodedSize(url)
            #expect(size == (64, 64))
        }
    }

    @Test func nonBitmapsAreRejected() {
        let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>"#.utf8)
        #expect(IconNormalizer.normalizedDataUrl(imageBytes: svg) == nil)
        #expect(IconNormalizer.normalizedDataUrl(imageBytes: Data("nope".utf8)) == nil)
    }

    @Test func dataUrlBytesHandlesBase64AndPercentEncoding() {
        #expect(IconNormalizer.dataUrlBytes("data:text/plain;base64,aGk=") == Data("hi".utf8))
        #expect(IconNormalizer.dataUrlBytes("data:image/svg+xml,%3Csvg%3E") == Data("<svg>".utf8))
        #expect(IconNormalizer.dataUrlBytes("data:nocomma") == nil)
        #expect(IconNormalizer.dataUrlBytes("https://example.com/a.png") == nil)
    }

    @Test func resolveNormalisesDataAndUrlIconsOnceEachAndKeepsEmoji() async throws {
        let png = Self.png(width: 32, height: 32)
        let embedded = "data:image/png;base64,\(png.base64EncodedString())"
        let fetched = FetchLog()
        let entries = [
            VaultEntryPlaintext(issuer: "A", accountName: "", secret: "S", icon: embedded),
            VaultEntryPlaintext(issuer: "B", accountName: "", secret: "S", icon: "https://x.test/b.png"),
            VaultEntryPlaintext(issuer: "C", accountName: "", secret: "S", icon: "https://x.test/b.png"),
            VaultEntryPlaintext(issuer: "D", accountName: "", secret: "S", icon: "https://x.test/404"),
            VaultEntryPlaintext(issuer: "E", accountName: "", secret: "S", icon: "🔑"),
            VaultEntryPlaintext(issuer: "F", accountName: "", secret: "S", icon: nil),
        ]
        #expect(ImportIcons.pendingCount(entries) == 3)

        let progress = FetchLog()
        let resolved = await ImportIcons.resolve(entries, fetch: { url in
            await fetched.append(url.absoluteString)
            return url.lastPathComponent == "b.png" ? png : nil
        }, progress: { done, total in await progress.append("\(done)/\(total)") })

        #expect(await fetched.items == ["https://x.test/b.png", "https://x.test/404"])
        #expect(await progress.items == ["1/3", "2/3", "3/3"])
        #expect(try decodedSize(try #require(resolved[0].icon)) == (64, 64))
        #expect(resolved[1].icon == resolved[2].icon && resolved[1].icon?.hasPrefix("data:image/png") == true)
        #expect(resolved[3].icon == nil)        // unreachable icon is dropped
        #expect(resolved[4].icon == "🔑")
        #expect(resolved[5].icon == nil)
    }
}

actor FetchLog {
    private(set) var items: [String] = []
    func append(_ item: String) { items.append(item) }
}
