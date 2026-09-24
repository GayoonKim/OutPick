import Foundation
import ImageIO
import Photos
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import OutPick

struct PhotoLibraryOriginalResourceTests {
    @Test @MainActor func photosPreparationUsesRealExtensionAndCleansOnlyItsOwnCopy() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let data = try #require(image.jpegData(compressionQuality: 0.9))
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoOriginal-\(UUID().uuidString).bin")
        try data.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let first = try PhotoLibraryPreparedResource(fileURL: source, isVideo: false)
        let second = try PhotoLibraryPreparedResource(fileURL: source, isVideo: false)
        defer { first.cleanup(); second.cleanup() }
        #expect(["jpg", "jpeg"].contains(first.fileURL.pathExtension))
        #expect(first.fileURL != source && first.fileURL != second.fileURL)
        #expect(try Data(contentsOf: first.fileURL) == data)
        first.cleanup()
        #expect(!FileManager.default.fileExists(atPath: first.fileURL.path))
        #expect(try Data(contentsOf: source) == data)
        #expect(try Data(contentsOf: second.fileURL) == data)
    }

    @Test @MainActor func binJPEGProvidesActualTypeWithoutChangingBytes() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let data = try #require(image.jpegData(compressionQuality: 0.8))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoOriginal-\(UUID().uuidString).bin")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let options = try PhotoLibraryOriginalResource.creationOptions(fileURL: url, isVideo: false)
        #expect(typeIdentifier(options) == UTType.jpeg.identifier)
        #expect(options.originalFilename?.hasSuffix(".jpeg") == true || options.originalFilename?.hasSuffix(".jpg") == true)
        #expect(options.shouldMoveFile == false)
        #expect(try Data(contentsOf: url) == data)
    }

    @Test @MainActor func extensionlessAnimatedGIFRetainsAllFramesAndType() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoOriginal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 2, nil))
        for color in [UIColor.red, .blue] {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            }
            CGImageDestinationAddImage(destination, try #require(image.cgImage), nil)
        }
        #expect(CGImageDestinationFinalize(destination))
        let before = try Data(contentsOf: url)
        let options = try PhotoLibraryOriginalResource.creationOptions(fileURL: url, isVideo: false)
        #expect(typeIdentifier(options) == UTType.gif.identifier)
        #expect(options.originalFilename?.hasSuffix(".gif") == true)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 2)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test @MainActor func misleadingJPEGExtensionStillUsesPNGContents() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoOriginal-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try #require(image.pngData()).write(to: url)
        let options = try PhotoLibraryOriginalResource.creationOptions(fileURL: url, isVideo: false)
        #expect(typeIdentifier(options) == UTType.png.identifier)
        #expect(options.originalFilename?.hasSuffix(".png") == true)
    }

    @Test func invalidFileIsRejectedBeforePhotosSubmission() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoOriginal-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not an image".utf8).write(to: url)
        #expect(throws: PhotoLibrarySaveError.saveFailed) {
            try PhotoLibraryOriginalResource.creationOptions(fileURL: url, isVideo: false)
        }
    }

    @Test func videoBrandOverridesMisleadingExtensionAndRejectsTruncatedAtom() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VideoType-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        // 20바이트 ftyp: QuickTime major/minor/compatible brand.
        let data = Data([0, 0, 0, 20]) + Data("ftypqt  ".utf8) + Data([0, 0, 0, 0]) + Data("qt  ".utf8)
        try data.write(to: url)
        let prepared = try PhotoLibraryPreparedResource(fileURL: url, isVideo: true)
        defer { prepared.cleanup() }
        #expect(prepared.fileURL.pathExtension == "mov")
        #expect(typeIdentifier(prepared.options) == UTType.quickTimeMovie.identifier)
        #expect(try Data(contentsOf: prepared.fileURL) == data)
        let unknown = url.deletingPathExtension().appendingPathExtension("bin")
        defer { try? FileManager.default.removeItem(at: unknown) }
        try Data(data.prefix(10)).write(to: unknown)
        #expect(throws: PhotoLibrarySaveError.saveFailed) {
            try PhotoLibraryOriginalResource.creationOptions(fileURL: unknown, isVideo: true)
        }
    }

    private func typeIdentifier(_ options: PHAssetResourceCreationOptions) -> String? {
        if #available(iOS 26, *) { options.contentType?.identifier }
        else { options.uniformTypeIdentifier }
    }
}
