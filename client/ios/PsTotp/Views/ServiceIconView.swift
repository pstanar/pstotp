import PsTotpCore
import SwiftUI
import UIKit

/// The entry's icon: an embedded image (data URL), an emoji, or a brand-coloured letter.
struct ServiceIconView: View {
    let issuer: String
    let icon: String?
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let image = Self.image(from: icon) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let icon, !icon.hasPrefix("data:") {
                ZStack {
                    Palette.surfaceVariant
                    Text(icon).font(.system(size: size / 1.8))
                }
            } else {
                let brand = ServiceBrands.get(issuer)
                ZStack {
                    brand.map { Color(argb: $0.bg) } ?? Palette.surfaceVariant
                    Text(brand?.letter ?? issuer.first.map { String($0).uppercased() } ?? "?")
                        .font(.system(size: size / 2, weight: .bold))
                        .foregroundStyle(brand.map { Color(argb: $0.fg) } ?? Palette.onSurfaceVariant)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private static let cache = NSCache<NSString, UIImage>()

    /// Decode `data:image/…;base64,…`; nil for anything else or undecodable data.
    private static func image(from icon: String?) -> UIImage? {
        guard let icon, icon.hasPrefix("data:"), let comma = icon.firstIndex(of: ",") else { return nil }
        let key = icon as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = Data(base64Encoded: String(icon[icon.index(after: comma)...]), options: .ignoreUnknownCharacters),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
