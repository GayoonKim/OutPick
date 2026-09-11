import CryptoKit
import Foundation
import ImageIO
import PhotosUI
import UniformTypeIdentifiers

enum ChatImageTransportSourceNormalizer {
    static let maxSourceBytes = ChatPhotoSizePolicy.maximumFileBytes
    static let maxThumbnailBytes = ChatPhotoSizePolicy.maximumFileBytes
    private static let mainQualities = [0.92, 0.80, 0.70]

    static func prepare(_ result: PHPickerResult, index: Int) async throws -> ProcessedImage {
        let sourceURL = try await loadOwnedFile(from: result.itemProvider)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        return try prepare(sourceURL: sourceURL, index: index)
    }

    static func prepare(sourceURL: URL, index: Int) throws -> ProcessedImage {
        try Task.checkCancellation()
        guard ChatPhotoSizePolicy.acceptsFile(bytes: fileBytes(sourceURL)) else {
            throw MediaError.sourceTooLarge
        }
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
        guard bytes > 0, bytes <= maxSourceBytes else {
            throw MediaError.sourceTooLarge
        }
        let outputURL = try outputURL(extension: "gif")
        try ChatGIFMetadataStripper.stripped(Data(contentsOf: sourceURL)).write(to: outputURL, options: .atomic)
        guard let image = normalizedSRGBImage(source: source, maxPixel: max(size.width, size.height)) else {
            try? FileManager.default.removeItem(at: outputURL)
            throw MediaError.failedToCreateImageData
        }
        let thumbURL: URL
        do { thumbURL = try makeThumbnailFile(image) }
        catch { try? FileManager.default.removeItem(at: outputURL); throw error }
        return ProcessedImage(
            index: index,
            originalFileURL: outputURL,
            thumbData: Data(),
            originalWidth: size.width,
            originalHeight: size.height,
            bytesOriginal: fileBytes(outputURL),
            sha256: sha256(outputURL),
            contentType: "image/gif",
            mediaFormat: "gif",
            isAnimated: CGImageSourceGetCount(source) > 1,
            thumbFileURL: thumbURL
        )
    }

    private static func prepareStatic(
        source: CGImageSource,
        index: Int,
        preservesPNG: Bool
    ) throws -> ProcessedImage {
        let outputType = preservesPNG ? UTType.png.identifier : UTType.jpeg.identifier
        let fileExtension = preservesPNG ? "png" : "jpg"
        let size = pixelSize(source)
        guard let image = normalizedSRGBImage(source: source, maxPixel: max(size.width, size.height)) else {
            throw MediaError.failedToConvertImage
        }
        for quality in preservesPNG ? [1.0] : mainQualities {
            try Task.checkCancellation()
            let outputURL = try outputURL(extension: fileExtension)
            guard let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                outputType as CFString,
                1,
                nil
            ) else { continue }
            let properties: [CFString: Any] = preservesPNG ? [:] : [
                kCGImageDestinationLossyCompressionQuality: quality
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
            let thumbURL: URL
            do { thumbURL = try makeThumbnailFile(image) }
            catch {
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }
            return ProcessedImage(
                index: index,
                originalFileURL: outputURL,
                thumbData: Data(),
                originalWidth: image.width,
                originalHeight: image.height,
                bytesOriginal: bytes,
                sha256: sha256(outputURL),
                contentType: preservesPNG ? "image/png" : "image/jpeg",
                mediaFormat: preservesPNG ? "png" : "jpeg",
                isAnimated: false,
                thumbFileURL: thumbURL
            )
        }
        throw MediaError.sourceTooLarge
    }

    /// 저장 해상도는 유지하고 JPEG 품질만 고정한다. 투명 영역은 검정으로 합성한다.
    static func makeThumbnailFile(_ image: CGImage, maximumBytes: Int = maxThumbnailBytes) throws -> URL {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw MediaError.failedToCreateImageData
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        let url = try outputURL(extension: "jpg")
        var keep = false
        defer { if !keep { try? FileManager.default.removeItem(at: url) } }
        guard let opaque = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw MediaError.failedToCreateImageData
        }
        CGImageDestinationAddImage(destination, opaque, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination), fileBytes(url) > 0,
              fileBytes(url) <= maximumBytes else { throw MediaError.sourceTooLarge }
        keep = true
        return url
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
