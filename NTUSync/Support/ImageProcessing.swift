import UIKit

/// Downscale + recompress user photos before they hit the store; a bench or
/// checkpoint photo never needs 48-megapixel originals.
@MainActor
enum ImageProcessing {
    static func jpegForStorage(_ data: Data,
                               maxDimension: CGFloat = 1600,
                               quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let largest = max(image.size.width, image.size.height)
        guard largest > maxDimension else { return image.jpegData(compressionQuality: quality) }

        let scale = maxDimension / largest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
