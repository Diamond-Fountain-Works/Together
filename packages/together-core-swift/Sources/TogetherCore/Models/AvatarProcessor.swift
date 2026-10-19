import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Legacy small-avatar compatibility only. New imports use MediaStore and preserve originals.
public enum AvatarProcessor {
    public static func source(from data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw TogetherError.invalid(Copy.text("copy.error.b8661cfa7d6d")) }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1024, kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw TogetherError.invalid(Copy.text("copy.error.b8661cfa7d6d")) }
        return image
    }
    public static func encode(_ image: CGImage, crop: AvatarCrop = AvatarCrop()) throws -> Data {
        let zoom = min(3, max(1, crop.zoom))
        let edge = Double(min(image.width, image.height)) / zoom
        let x = (Double(image.width) - edge) * (min(1, max(-1, crop.horizontal)) + 1) / 2
        let y = (Double(image.height) - edge) * (min(1, max(-1, crop.vertical)) + 1) / 2
        guard let cropped = image.cropping(to: CGRect(x: x, y: y, width: edge, height: edge)) else { throw TogetherError.invalid(Copy.text("copy.error.cf2221ca27c2")) }
        for dimension in [512, 384, 256] {
            let size = min(dimension, max(1, Int(edge)))
            guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
            context.interpolationQuality = .high
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: size, height: size))
            guard let resized = context.makeImage() else { continue }
            for quality in [0.9, 0.75, 0.6, 0.45] {
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
                CGImageDestinationAddImage(destination, resized, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                if CGImageDestinationFinalize(destination), output.length <= 131_072 { return output as Data }
            }
        }
        throw TogetherError.invalid(Copy.text("copy.error.fecb75aa6313"))
    }
}
