import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import OutPick

final class ChatDirectMediaPreparationTests: XCTestCase {
    func testSourceAbove300MBFailsBeforeDecode() throws {
        let input = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: input) }
        XCTAssertTrue(FileManager.default.createFile(atPath: input.path, contents: nil))
        let handle = try FileHandle(forWritingTo: input)
        try handle.truncate(atOffset: 300_000_001)
        try handle.close()
        XCTAssertThrowsError(try ChatImageTransportSourceNormalizer.prepare(sourceURL: input, index: 0)) { error in
            guard case MediaError.sourceTooLarge = error else { return XCTFail("용량 검사가 디코딩보다 먼저 실행되어야 합니다.") }
        }
    }

    func testPhotoThumbnailAboveOld4MiBLimitIsAcceptedButVideoLimitIsKept() throws {
        let width = 4032, height = 3024
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var random: UInt32 = 12345
        for offset in stride(from: 0, to: width * height * 4, by: 4) {
            random ^= random << 13; random ^= random >> 17; random ^= random << 5
            pixels[offset] = UInt8(truncatingIfNeeded: random)
            pixels[offset + 1] = UInt8(truncatingIfNeeded: random >> 8)
            pixels[offset + 2] = UInt8(truncatingIfNeeded: random >> 16)
            pixels[offset + 3] = 255
        }
        let image = try XCTUnwrap(context.makeImage())
        let thumbnail = try ChatImageTransportSourceNormalizer.makeThumbnailFile(image)
        defer { try? FileManager.default.removeItem(at: thumbnail) }
        let bytes = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: thumbnail.path)[.size] as? NSNumber).intValue
        XCTAssertGreaterThan(bytes, 4 * 1024 * 1024)
        XCTAssertLessThanOrEqual(bytes, 300_000_000)
        XCTAssertThrowsError(try ChatImageTransportSourceNormalizer.makeThumbnailFile(image, maximumBytes: 4 * 1024 * 1024))
    }

    func testMainAndThumbnailKeepPixelsAboveOldLimit() throws {
        let input = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: input) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 4800, height: 4, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(input as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let prepared = try ChatImageTransportSourceNormalizer.prepare(sourceURL: input, index: 0)
        defer {
            try? FileManager.default.removeItem(at: prepared.originalFileURL)
            if let url = prepared.thumbFileURL { try? FileManager.default.removeItem(at: url) }
        }
        XCTAssertEqual(prepared.originalWidth, 4800)
        XCTAssertEqual(prepared.originalHeight, 4)
        for url in [prepared.originalFileURL, try XCTUnwrap(prepared.thumbFileURL)] {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 4800)
            XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 4)
        }
    }

    func testGIFStripsCommentWithoutChangingFrameBlocks() throws {
        let clean = try XCTUnwrap(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="))
        var annotated = clean.dropLast()
        annotated.append(contentsOf: [0x21, 0xFE, 3, 65, 66, 67, 0, 0x3B])
        XCTAssertEqual(try ChatGIFMetadataStripper.stripped(Data(annotated)), clean)
        XCTAssertThrowsError(try ChatGIFMetadataStripper.stripped(clean.dropLast()))
    }

    func testGIFKeepsLoopAndBothFrameBlocks() throws {
        let single = try XCTUnwrap(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="))
        let bytes = [UInt8](single)
        let frameStart = try XCTUnwrap(bytes.firstIndex(of: 0x2C))
        var animated = Data(bytes[..<frameStart])
        animated.append(contentsOf: [0x21, 0xFF, 11])
        animated.append(Data("NETSCAPE2.0".utf8))
        animated.append(contentsOf: [3, 1, 0, 0, 0])
        for delay: UInt8 in [5, 20] {
            animated.append(contentsOf: [0x21, 0xF9, 4, 0, delay, 0, 0, 0])
            animated.append(contentsOf: bytes[frameStart..<(bytes.count - 1)])
        }
        animated.append(0x3B)
        XCTAssertEqual(try ChatGIFMetadataStripper.stripped(animated), animated)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(animated as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 2)
    }

    func testByteWeightedProgressIncludesThumbnailWithoutCountingRetriesTwice() {
        var values: [Double] = []
        let progress = ChatMediaBatchProgress(completed: 0, total: 100, weights: [90, 10]) { values.append($0) }
        progress.update(index: 1, fraction: 1)
        progress.update(index: 0, fraction: 0.5)
        progress.update(index: 0, fraction: 0.2)
        progress.update(index: 0, fraction: 1)
        XCTAssertEqual(values, [0.1, 0.55, 0.55, 1])
    }
}
