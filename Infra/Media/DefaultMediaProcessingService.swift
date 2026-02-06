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
    private init() {}

    // MARK: - 썸네일 설정
    /// 기본 썸네일 긴 변(px)
    static let defaultThumbMaxPixel: Int = 500
    /// 기본 JPEG 품질
    static let defaultThumbQuality: CGFloat = 0.5

    // MARK: - Video presets
    enum VideoUploadPreset {
        case dataSaver720    // ~2.0–2.5 Mbps, 720p
        case standard720     // ~4.0–5.0 Mbps, 720p (권장 기본)
        case high1080        // ~6.0–8.0 Mbps, 1080p
    }

    // MARK: - 내부 공통(썸네일/메타) 헬퍼

    /// 내부 공통: CGImageSource -> 썸네일 JPEG 데이터
    private static func makeThumbnailData(from source: CGImageSource,
                                          maxPixel: Int,
                                          quality: CGFloat) -> Data? {
        let opts: [NSString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgThumb).jpegData(compressionQuality: quality)
    }

    /// 썸네일 데이터 생성(UIImage 입력)
    static func makeThumbnailData(from image: UIImage,
                                  maxPixel: Int = DefaultMediaProcessingService.defaultThumbMaxPixel,
                                  quality: CGFloat = DefaultMediaProcessingService.defaultThumbQuality) -> Data? {
        // 주: 여기서 재인코딩이 한 번 일어남. 가능하면 URL 기반 API를 쓰는 게 메모리/성능에 유리.
        guard let imageData = image.jpegData(compressionQuality: 1.0),
              let src = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return nil
        }
        return makeThumbnailData(from: src, maxPixel: maxPixel, quality: quality)
    }

    /// 썸네일 데이터 생성(URL 입력)
    static func makeThumbnailData(from url: URL,
                                  maxPixel: Int = DefaultMediaProcessingService.defaultThumbMaxPixel,
                                  quality: CGFloat = DefaultMediaProcessingService.defaultThumbQuality) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return makeThumbnailData(from: src, maxPixel: maxPixel, quality: quality)
    }

    /// (이전 호환) 썸네일 CGImage 반환
    @available(*, deprecated, message: "Use makeThumbnailData(from:maxPixel:quality:) that returns Data instead.")
    static func compressImageWithImageIO(_ image: UIImage) -> CGImage? {
        guard let data = makeThumbnailData(from: image, maxPixel: 500, quality: 0.5),
              let ui = UIImage(data: data),
              let cg = ui.cgImage else {
            print("압축 이미지 데이터 생성 실패")
            return nil
        }
        return cg
    }

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

    // MARK: - ImagePair (내부 업로드 흐름과의 호환 유지용)

    struct ImagePair {
        let index: Int
        let originalFileURL: URL
        let thumbData: Data
        let originalWidth: Int
        let originalHeight: Int
        let bytesOriginal: Int
        let sha256: String

        var fileBaseName: String { sha256 }
    }

    // MARK: - Image processing (기존 API)

    func makePair(
        from result: PHPickerResult,
        index: Int,
        thumbMaxPixel: Int = DefaultMediaProcessingService.defaultThumbMaxPixel,
        thumbQuality: CGFloat = DefaultMediaProcessingService.defaultThumbQuality
    ) async throws -> ImagePair {
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

                guard let thumb = DefaultMediaProcessingService.makeThumbnailData(from: source,
                                                                                 maxPixel: thumbMaxPixel,
                                                                                 quality: thumbQuality) else {
                    continuation.resume(throwing: MediaError.failedToCreateImageData)
                    return
                }

                let hash = DefaultMediaProcessingService.sha256(of: ownedURL)
                let bytes = DefaultMediaProcessingService.fileBytes(of: ownedURL)

                continuation.resume(returning: ImagePair(
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

    func preparePairs(_ results: [PHPickerResult]) async throws -> [ImagePair] {
        try await withThrowingTaskGroup(of: ImagePair.self) { group in
            for (i, r) in results.enumerated() {
                group.addTask { [self] in
                    try await makePair(from: r, index: i)
                }
            }

            var list = Array<ImagePair?>(repeating: nil, count: results.count)
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
                // - 현재는 FYVideoCompressor 경로를 잠시 비활성화하고, exportSession 기반으로 결과/호환성 확인
                // - high1080 프리셋도 테스트 단계에서는 720p로 강제(필요 시 1080p 프리셋 구현 추가)
                Task {
                    do {
                        let compressedURL = try await AVAssetExportVideoCompressor.compress720pMP4(inputURL: ownedURL)
                        continuation.resume(returning: compressedURL)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }

                /*
                // 🔻 기존 경로(잠시 비활성화): FYVideoCompressor 기반 압축
                let asset = AVAsset(url: ownedURL)
                let size = self.targetSize(for: asset, preset: preset)
                let bitrate = self.bitrate(for: preset)

                let gopIntervalAssumingFrames = 60

                let config = FYVideoCompressor.CompressionConfig(
                    videoBitrate: bitrate,
                    videomaxKeyFrameInterval: gopIntervalAssumingFrames,
                    fps: 30,
                    audioSampleRate: 48_000,
                    audioBitrate: 128_000,
                    fileType: .mp4,   // 확실하지 않음: 라이브러리 내부 코덱 정책은 문서 확인 필요
                    scale: size
                )

                FYVideoCompressor().compressVideo(ownedURL, config: config) { result in
                    switch result {
                    case .success(let compressedVideoURL):
                        continuation.resume(returning: compressedVideoURL)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                */
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

    // MARK: - MediaProcessingServiceProtocol 구현 (Prepared* 반환)

    func prepareImages(_ results: [PHPickerResult]) async throws -> [PreparedImage] {
        let pairs = try await preparePairs(results)
        return pairs.map {
            PreparedImage(
                index: $0.index,
                originalFileURL: $0.originalFileURL,
                thumbData: $0.thumbData,
                originalWidth: $0.originalWidth,
                originalHeight: $0.originalHeight,
                bytesOriginal: $0.bytesOriginal,
                sha256: $0.sha256
            )
        }
    }

    func prepareVideo(_ result: PHPickerResult,
                      preset: VideoUploadPreset) async throws -> PreparedVideo {
        let compressedURL = try await convertVideo(result, preset: preset)

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
            duration: safeDuration,
            width: w,
            height: h,
            sizeBytes: sizeBytes,
            approxBitrateMbps: approxBitrateMbps,
            preset: preset
        )
    }
}

