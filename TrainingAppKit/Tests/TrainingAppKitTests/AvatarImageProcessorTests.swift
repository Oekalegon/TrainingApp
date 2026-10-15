import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import TrainingAppKit

@Suite("AvatarImageProcessor (MVP2-132)")
struct AvatarImageProcessorTests {
    /// A solid-color image of the given size, encoded as PNG.
    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func decodedSize(of data: Data) throws -> (width: Int, height: Int, type: String?) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height, CGImageSourceGetType(source) as String?)
    }

    @Test("a large landscape photo becomes a 256-pixel square JPEG, small enough to keep on the profile")
    func largePhotoBecomesSmallSquare() throws {
        let result = try #require(AvatarImageProcessor.processedAvatar(from: pngData(width: 2400, height: 1600)))

        let size = try decodedSize(of: result)
        #expect(size.width == AvatarImageProcessor.sideLength)
        #expect(size.height == AvatarImageProcessor.sideLength)
        #expect(size.type == UTType.jpeg.identifier)
        #expect(result.count < 100_000)
    }

    @Test("a tall photo is cropped to a square too")
    func tallPhotoIsSquare() throws {
        let result = try #require(AvatarImageProcessor.processedAvatar(from: pngData(width: 900, height: 1800)))

        let size = try decodedSize(of: result)
        #expect(size.width == size.height)
    }

    @Test("an image smaller than the target keeps its size instead of being enlarged")
    func smallImageIsNotEnlarged() throws {
        let result = try #require(AvatarImageProcessor.processedAvatar(from: pngData(width: 100, height: 60)))

        let size = try decodedSize(of: result)
        #expect(size.width == 60)
        #expect(size.height == 60)
    }

    @Test("data that isn't an image gives nothing")
    func notAnImage() {
        #expect(AvatarImageProcessor.processedAvatar(from: Data("not an image".utf8)) == nil)
        #expect(AvatarImageProcessor.processedAvatar(from: Data()) == nil)
    }
}
