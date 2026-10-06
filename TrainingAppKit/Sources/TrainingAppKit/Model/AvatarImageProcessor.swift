import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns a picture the athlete picked into the small square JPEG kept on their profile (MVP2-132).
///
/// The profile is saved, synced and re-saved on every edit, so the picture is cut to a centered
/// square and scaled to ``sideLength`` pixels, which keeps it to a few tens of kilobytes whatever the
/// photo's size. Works on `ImageIO` rather than `UIKit`, so it also runs in the package's macOS tests.
public enum AvatarImageProcessor {
    /// The picture's width and height in pixels.
    public static let sideLength = 256

    /// The square JPEG for `data`, or `nil` when it isn't an image `ImageIO` can read.
    ///
    /// Smaller images keep their size rather than being enlarged; the result is always square.
    ///
    /// - Parameter data: The picked image in any format the system can decode, e.g. HEIC or PNG.
    public static func processedAvatar(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        // Decodes at reduced size straight from the file, applying the photo's orientation, so a large
        // photo is never held in memory at full resolution.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: sideLength * 2,
        ]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let side = min(scaled.width, scaled.height)
        let square = CGRect(x: (scaled.width - side) / 2, y: (scaled.height - side) / 2, width: side, height: side)
        guard let cropped = scaled.cropping(to: square) else { return nil }
        let finalSide = min(side, sideLength)
        guard let context = CGContext(
            data: nil, width: finalSide, height: finalSide, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: finalSide, height: finalSide))
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
