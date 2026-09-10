import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import OutPick

final class ChatDirectMediaPreparationTests: XCTestCase {
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
