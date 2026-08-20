import CryptoKit
import Foundation
import ImageIO
import PhotosUI
import UniformTypeIdentifiers

enum ChatImageTransportSourceNormalizer {
    static let maxSourceBytes = 15 * 1024 * 1024
    static let maxLongEdge = 4_096
    private static let fallbackLongEdges = [4_096, 3_584, 3_072, 2_560, 2_048, 1_536, 1_280, 1_024, 768, 512]

    static func prepare(_ result: PHPickerResult, index: Int) async throws -> ProcessedImage {
        let sourceURL = try await loadOwnedFile(from: result.itemProvider)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let sourceType = CGImageSourceGetType(source) else {
            throw MediaError.failedToConvertImage
        }

        if UTType(sourceType as String)?.conforms(to: .gif) == true {
            return try prepareGIF(sourceURL: sourceURL, source: source, index: index)
        }
        let preservesPNG = UTType(sourceType as String)?.conforms(to: .png) == true
        return try prepareStatic(source: source, index: index, preservesPNG: preservesPNG)
    }

    private static func prepareGIF(
        sourceURL: URL,
        source: CGImageSource,
        index: Int
    ) throws -> ProcessedImage {
        let size = pixelSize(source)
        let bytes = fileBytes(sourceURL)
        guard bytes > 0, bytes <= maxSourceBytes,
              max(size.width, size.height) <= maxLongEdge else {
            throw MediaError.sourceTooLarge
        }
        let outputURL = try outputURL(extension: "gif")
        try FileManager.default.copyItem(at: sourceURL, to: outputURL)
        guard let thumb = ImageThumbnailDataMaker.makeData(from: source) else {
            throw MediaError.failedToCreateImageData
        }
        return ProcessedImage(
            index: index,
            originalFileURL: outputURL,
            thumbData: thumb,
            originalWidth: size.width,
            originalHeight: size.height,
            bytesOriginal: bytes,
            sha256: sha256(outputURL),
            contentType: "image/gif",
            mediaFormat: "gif",
            isAnimated: CGImageSourceGetCount(source) > 1
        )
    }

    private static func prepareStatic(
        source: CGImageSource,
        index: Int,
        preservesPNG: Bool
    ) throws -> ProcessedImage {
        let outputType = preservesPNG ? UTType.png.identifier : UTType.jpeg.identifier
        let fileExtension = preservesPNG ? "png" : "jpg"
        for maxPixel in fallbackLongEdges {
            guard let image = normalizedSRGBImage(source: source, maxPixel: maxPixel) else { continue }
            let outputURL = try outputURL(extension: fileExtension)
            guard let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                outputType as CFString,
                1,
                nil
            ) else { continue }
            let properties: [CFString: Any] = preservesPNG ? [:] : [
                kCGImageDestinationLossyCompressionQuality: 0.92
            ]
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                try? FileManager.default.removeItem(at: outputURL)
                continue
            }
            let bytes = fileBytes(outputURL)
            guard bytes > 0, bytes <= maxSourceBytes else {
                try? FileManager.default.removeItem(at: outputURL)
                continue
            }
            guard let normalizedSource = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
                  let thumb = ImageThumbnailDataMaker.makeData(from: normalizedSource) else {
                try? FileManager.default.removeItem(at: outputURL)
                continue
            }
            return ProcessedImage(
                index: index,
                originalFileURL: outputURL,
                thumbData: thumb,
                originalWidth: image.width,
                originalHeight: image.height,
                bytesOriginal: bytes,
                sha256: sha256(outputURL),
                contentType: preservesPNG ? "image/png" : "image/jpeg",
                mediaFormat: preservesPNG ? "png" : "jpeg",
                isAnimated: false
            )
        }
        throw MediaError.sourceTooLarge
    }

    private static func normalizedSRGBImage(source: CGImageSource, maxPixel: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: decoded.width,
                height: decoded.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height))
        return context.makeImage()
    }

    private static func loadOwnedFile(from provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            guard provider.hasRepresentationConforming(toTypeIdentifier: UTType.image.identifier) else {
                continuation.resume(throwing: MediaError.unsupportedType)
                return
            }
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                guard let url, error == nil else {
                    continuation.resume(throwing: error ?? MediaError.failedToConvertImage)
                    return
                }
                do {
                    let owned = FileManager.default.temporaryDirectory
                        .appendingPathComponent("chat-image-source", isDirectory: true)
                    try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
                    let destination = owned.appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension.isEmpty ? "dat" : url.pathExtension)
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func outputURL(extension fileExtension: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-transport-source", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
    }

    private static func pixelSize(_ source: CGImageSource) -> (width: Int, height: Int) {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return (
            properties?[kCGImagePropertyPixelWidth] as? Int ?? 0,
            properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        )
    }

    private static func fileBytes(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    }

    private static func sha256(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
