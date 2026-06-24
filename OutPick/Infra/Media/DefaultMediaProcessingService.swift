//
//  DefaultMediaProcessingService.swift
//  OutPick
//
//  Created by 김가윤 on 1/10/25.
//

import UIKit
import PhotosUI
import ImageIO
//import FYVideoCompressor
import UniformTypeIdentifiers
import CryptoKit
import AVFoundation

/// 본체: 미디어 가공/변환 서비스
/// - MainActor가 필요 없는 IO/가공 로직이므로 actor 격리하지 않음
final class DefaultMediaProcessingService: @unchecked Sendable, MediaProcessingServiceProtocol {

    static let shared = DefaultMediaProcessingService()
    init() {}

    /// 원본 픽셀 크기 추출
    private static func pixelSize(from source: CGImageSource) -> (Int, Int) {
        guard
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let w = props[kCGImagePropertyPixelWidth] as? Int,
            let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return (0, 0) }
        return (w, h)
    }

    /// 파일 내용 기반 SHA-256
    private static func sha256(of url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 파일 크기(bytes)
    private static func fileBytes(of url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    }

    /// PHPicker 임시 URL을 앱 소유 임시 디렉터리로 복사
    private static func copyToAppTemporary(from src: URL) throws -> URL {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent("picked-images", isDirectory: true)
        try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let ext = src.pathExtension.isEmpty ? "dat" : src.pathExtension
        let dst = baseDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)

        if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
        try fm.copyItem(at: src, to: dst)
        return dst
    }

    /// 비디오 실제 표시 해상도 추출(preferredTransform 반영)
    private static func videoSize(from asset: AVAsset) -> (Int, Int) {
        guard let track = asset.tracks(withMediaType: .video).first else { return (0, 0) }
        let natural = track.naturalSize
        let t = track.preferredTransform
        let transformed = natural.applying(t)
        let w = Int(abs(transformed.width))
        let h = Int(abs(transformed.height))
        if w > 0, h > 0 { return (w, h) }
        return (Int(natural.width), Int(natural.height))
    }

    /// 비디오 썸네일 생성(JPEG Data)
    private static func makeVideoThumbnailData(url: URL) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceAfter = .zero
            generator.requestedTimeToleranceBefore = .zero

            let time = CMTime(seconds: 0.0, preferredTimescale: 600)

            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard result == .succeeded, let cgImage = cgImage else {
                    continuation.resume(returning: nil)
                    return
                }
                let ui = UIImage(cgImage: cgImage)
                let data = ui.jpegData(compressionQuality: 0.7)
                continuation.resume(returning: data)
            }
        }
    }

    // MARK: - Image processing (기존 API)

    func makePair(
        from result: PHPickerResult,
        index: Int
    ) async throws -> ProcessedImage {
        try await makePair(
            from: result,
            index: index,
            thumbMaxPixel: ImageThumbnailDataMaker.defaultMaxPixel,
            thumbQuality: ImageThumbnailDataMaker.defaultQuality
        )
    }

    func makePair(
        from result: PHPickerResult,
        index: Int,
        thumbMaxPixel: Int = ImageThumbnailDataMaker.defaultMaxPixel,
        thumbQuality: CGFloat = ImageThumbnailDataMaker.defaultQuality
    ) async throws -> ProcessedImage {
        try await withCheckedThrowingContinuation { continuation in
            let itemProvider = result.itemProvider

            guard itemProvider.hasRepresentationConforming(toTypeIdentifier: UTType.image.identifier) else {
                continuation.resume(throwing: MediaError.unsupportedType)
                return
            }

            itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { fileURL, error in
                guard let fileURL = fileURL, error == nil else {
                    continuation.resume(throwing: error ?? MediaError.failedToConvertImage)
                    return
                }

                let ownedURL: URL
                do {
                    ownedURL = try DefaultMediaProcessingService.copyToAppTemporary(from: fileURL)
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                guard let source = CGImageSourceCreateWithURL(ownedURL as CFURL, nil) else {
                    continuation.resume(throwing: MediaError.failedToConvertImage)
                    return
                }

                let (ow, oh) = DefaultMediaProcessingService.pixelSize(from: source)

                guard let thumb = ImageThumbnailDataMaker.makeData(
                    from: source,
                    maxPixel: thumbMaxPixel,
                    quality: thumbQuality
                ) else {
                    continuation.resume(throwing: MediaError.failedToCreateImageData)
                    return
                }

                let hash = DefaultMediaProcessingService.sha256(of: ownedURL)
                let bytes = DefaultMediaProcessingService.fileBytes(of: ownedURL)

                continuation.resume(returning: ProcessedImage(
                    index: index,
                    originalFileURL: ownedURL,
                    thumbData: thumb,
                    originalWidth: ow,
                    originalHeight: oh,
                    bytesOriginal: bytes,
                    sha256: hash
                ))
            }
        }
    }

    func preparePairs(_ results: [PHPickerResult]) async throws -> [ProcessedImage] {
        try await withThrowingTaskGroup(of: ProcessedImage.self) { group in
            for (i, r) in results.enumerated() {
                group.addTask { [self] in
                    try await makePair(from: r, index: i)
                }
            }

            var list = Array<ProcessedImage?>(repeating: nil, count: results.count)
            for try await pair in group {
                list[pair.index] = pair
            }
            return list.compactMap { $0 }
        }
    }

    // MARK: - Video conversion (기존 API)

    private func bitrate(for preset: VideoUploadPreset) -> Int {
        switch preset {
        case .dataSaver720:  return 2_400_000
        case .standard720:   return 4_500_000
        case .high1080:      return 7_000_000
        }
    }

    private func targetSize(for asset: AVAsset, preset: VideoUploadPreset) -> CGSize {
        guard let track = asset.tracks(withMediaType: .video).first else {
            switch preset {
            case .high1080: return CGSize(width: 1920, height: 1080)
            default:        return CGSize(width: 1280, height: 720)
            }
        }

        let natural = track.naturalSize
        let t = track.preferredTransform
        let isPortrait = (t.a == 0 && abs(t.b) == 1 && abs(t.c) == 1 && t.d == 0)

        let srcW = isPortrait ? natural.height : natural.width
        let srcH = isPortrait ? natural.width  : natural.height
        let aspect = max(srcW, 1) / max(srcH, 1)

        let longSide: CGFloat = (preset == .high1080) ? 1920 : 1280
        var outW: CGFloat
        var outH: CGFloat

        if srcW >= srcH {
            outW = longSide
            outH = (longSide / max(aspect, 0.01))
        } else {
            outH = longSide
            outW = (longSide * max(aspect, 0.01))
        }

        // 인코더 호환성 위해 짝수 픽셀 보장
        outW = floor(outW / 2) * 2
        outH = floor(outH / 2) * 2
        return CGSize(width: max(outW, 2), height: max(outH, 2))
    }

    func convertVideo(_ result: PHPickerResult, preset: VideoUploadPreset = .standard720) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let itemProvider = result.itemProvider

            guard itemProvider.hasRepresentationConforming(toTypeIdentifier: UTType.movie.identifier) else {
                continuation.resume(throwing: MediaError.unsupportedType)
                return
            }

            itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { fileURL, error in
                guard let fileURL = fileURL, error == nil else {
                    continuation.resume(throwing: error ?? MediaError.failedToConvertImage)
                    return
                }

                let ownedURL: URL
                do {
                    ownedURL = try DefaultMediaProcessingService.copyToAppTemporary(from: fileURL)
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // iOS 순정 AVAssetExportSession 프리셋 기반(720p) 압축기 사용
                // - high1080 프리셋도 테스트 단계에서는 720p로 강제(필요 시 1080p 프리셋 구현 추가)
                Task {
                    do {
                        let compressedURL = try await AVAssetExportVideoCompressor.compress720pMP4(inputURL: ownedURL)
                        continuation.resume(returning: compressedURL)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    func dealWithVideos(_ results: [PHPickerResult], preset: VideoUploadPreset = .standard720) async throws -> [URL] {
        try await withThrowingTaskGroup(of: (Int, URL).self) { group in
            for (index, result) in results.enumerated() {
                group.addTask { [self] in
                    let url = try await convertVideo(result, preset: preset)
                    return (index, url)
                }
            }

            var inOrder = Array<URL?>(repeating: nil, count: results.count)
            for try await (index, url) in group {
                inOrder[index] = url
            }
            return inOrder.compactMap { $0 }
        }
    }

    // MARK: - MediaProcessingServiceProtocol 구현

    func prepareImages(_ results: [PHPickerResult]) async throws -> [ProcessedImage] {
        try await preparePairs(results)
    }

    func prepareVideo(_ result: PHPickerResult,
                      preset: VideoUploadPreset) async throws -> PreparedVideo {
        let compressedURL = try await convertVideo(result, preset: preset)
        let sha = DefaultMediaProcessingService.sha256(of: compressedURL)

        let asset = AVAsset(url: compressedURL)
        let durationSeconds = CMTimeGetSeconds(asset.duration)
        let safeDuration = (durationSeconds.isFinite && durationSeconds > 0) ? durationSeconds : 0

        let (w, h) = DefaultMediaProcessingService.videoSize(from: asset)
        let sizeBytes = Int64(DefaultMediaProcessingService.fileBytes(of: compressedURL))

        let approxBitrateMbps: Double
        if safeDuration > 0 {
            approxBitrateMbps = (Double(sizeBytes) * 8.0) / safeDuration / 1_000_000.0
        } else {
            approxBitrateMbps = 0
        }

        guard let thumbData = try await DefaultMediaProcessingService.makeVideoThumbnailData(url: compressedURL) else {
            throw MediaError.failedToCreateImageData
        }

        return PreparedVideo(
            compressedFileURL: compressedURL,
            thumbnailData: thumbData,
            sha256: sha,
            duration: safeDuration,
            width: w,
            height: h,
            sizeBytes: sizeBytes,
            approxBitrateMbps: approxBitrateMbps,
            preset: preset
        )
    }
}
