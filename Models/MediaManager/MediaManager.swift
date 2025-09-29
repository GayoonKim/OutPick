//
//  MediaManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/10/25.
//

import UIKit
import PhotosUI
import ImageIO
import FYVideoCompressor
import UniformTypeIdentifiers
import CryptoKit
import AVFoundation

class MediaManager {
    
    static let shared = MediaManager()
    
    // MARK: - Thumbnail Tunables (raised quality)
    /// 기본 썸네일 긴 변(px). 기존 64 → 160 으로 상향 (셀에서 더 선명)
    static let defaultThumbMaxPixel: Int = 500
    /// 기본 JPEG 품질. 기존 0.6 → 0.8 으로 상향
    static let defaultThumbQuality: CGFloat = 0.5
    
    // MARK: - Thumbnail helpers

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

    /// 썸네일 데이터 생성(UIImage 입력) - 기존 compressImageWithImageIO 대체
    static func makeThumbnailData(from image: UIImage,
                                  maxPixel: Int = MediaManager.defaultThumbMaxPixel,
                                  quality: CGFloat = MediaManager.defaultThumbQuality) -> Data? {
        // 주: 여기서 재인코딩이 한 번 일어남. 가능하면 URL 기반 API를 쓰는 게 메모리/성능에 유리.
        guard let imageData = image.jpegData(compressionQuality: 1.0),
              let src = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return nil
        }
        return makeThumbnailData(from: src, maxPixel: maxPixel, quality: quality)
    }

    /// 썸네일 데이터 생성(URL 입력) - PHPicker loadFileRepresentation 경로에 적합
    static func makeThumbnailData(from url: URL,
                                  maxPixel: Int = MediaManager.defaultThumbMaxPixel,
                                  quality: CGFloat = MediaManager.defaultThumbQuality) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return makeThumbnailData(from: src, maxPixel: maxPixel, quality: quality)
    }

    /// (이전 호환) 썸네일 CGImage 반환 - 신규 Data 기반 API로 라우팅
    @available(*, deprecated, message: "Use makeThumbnailData(from:maxPixel:quality:) that returns Data instead. Defaults now produce sharper thumbnails (160px / q=0.8).")
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

    /// 파일 내용 기반 SHA-256 (파일명/중복제거/캐시 키용)
    private static func sha256(of url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Pairs (thumbnail + original only)

    /// 2종 파생본(썸네일 + 원본 메타) 업로드 준비용
    struct ImagePair {
        let index: Int
        let originalFileURL: URL
        let thumbData: Data
        let originalWidth: Int
        let originalHeight: Int
        let bytesOriginal: Int
        let sha256: String

        var fileBaseName: String { sha256 } // 경로/파일명/캐시 키로 사용
    }

    /// 파일 크기(bytes)
    private static func fileBytes(of url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    }

    /// PHPicker가 제공한 임시 파일 URL을 앱이 소유한 임시 디렉터리로 복사
    /// - Important: loadFileRepresentation 콜백이 끝나면 원본 임시 URL은 사라질 수 있으므로 반드시 복사해야 안전함.
    private static func copyToAppTemporary(from src: URL) throws -> URL {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent("picked-images", isDirectory: true)
        // 디렉터리 보장
        try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        let ext = src.pathExtension.isEmpty ? "dat" : src.pathExtension
        let dst = baseDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        // 혹시 남아있다면 제거 후 복사
        if fm.fileExists(atPath: dst.path) {
            try? fm.removeItem(at: dst)
        }
        try fm.copyItem(at: src, to: dst)
        return dst
    }

    /// PHPicker 1개 결과 -> (썸네일 + 원본 URL)
    /// - Parameters:
    ///   - result: PHPickerResult
    ///   - index: 첨부 순서
    ///   - thumbMaxPixel: 썸네일 긴 변(기본 64px)
    ///   - thumbQuality: JPEG 품질(기본 0.6)
    func makePair(
        from result: PHPickerResult,
        index: Int,
        thumbMaxPixel: Int = MediaManager.defaultThumbMaxPixel,
        thumbQuality: CGFloat = MediaManager.defaultThumbQuality
    ) async throws -> ImagePair {
        try await withCheckedThrowingContinuation { continuation in
            let itemProvider = result.itemProvider
            guard itemProvider.hasRepresentationConforming(toTypeIdentifier: UTType.image.identifier) else {
                continuation.resume(throwing: NSError(domain: "MediaManager", code: -200, userInfo: [NSLocalizedDescriptionKey: "지원되지 않는 이미지 타입"]))
                return
            }
            itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { fileURL, error in
                guard let fileURL = fileURL, error == nil else {
                    continuation.resume(throwing: error ?? NSError(domain: "MediaManager", code: -201, userInfo: [NSLocalizedDescriptionKey: "이미지 파일 URL 로드 실패"]))
                    return
                }
                // 1) 앱 소유 임시 폴더로 복사 (loadFileRepresentation 콜백 이후 원본이 삭제될 수 있음)
                let ownedURL: URL
                do {
                    ownedURL = try MediaManager.copyToAppTemporary(from: fileURL)
                } catch {
                    continuation.resume(throwing: NSError(domain: "MediaManager", code: -204, userInfo: [NSLocalizedDescriptionKey: "임시 파일 복사 실패: \(error.localizedDescription)"]))
                    return
                }

                // 2) 파생 정보/썸네일 생성은 복사본(ownedURL) 기준으로 수행
                guard let source = CGImageSourceCreateWithURL(ownedURL as CFURL, nil) else {
                    continuation.resume(throwing: NSError(domain: "MediaManager", code: -202, userInfo: [NSLocalizedDescriptionKey: "CGImageSource 생성 실패"]))
                    return
                }
                let (ow, oh) = MediaManager.pixelSize(from: source)
                guard let thumb = MediaManager.makeThumbnailData(from: source, maxPixel: thumbMaxPixel, quality: thumbQuality) else {
                    continuation.resume(throwing: NSError(domain: "MediaManager", code: -203, userInfo: [NSLocalizedDescriptionKey: "썸네일 생성 실패"]))
                    return
                }
                let hash = MediaManager.sha256(of: ownedURL)
                let bytes = MediaManager.fileBytes(of: ownedURL)
                let pair = ImagePair(
                    index: index,
                    originalFileURL: ownedURL,
                    thumbData: thumb,
                    originalWidth: ow,
                    originalHeight: oh,
                    bytesOriginal: bytes,
                    sha256: hash
                )
                continuation.resume(returning: pair)
            }
        }
    }

    /// 여러 장을 순서 보장 (썸네일 + 원본) 배열로 변환
    func preparePairs(_ results: [PHPickerResult]) async throws -> [ImagePair] {
        try await withThrowingTaskGroup(of: ImagePair.self) { group in
            for (i, r) in results.enumerated() {
                group.addTask {
                    try await self.makePair(from: r, index: i)
                }
            }
            var list = Array<ImagePair?>(repeating: nil, count: results.count)
            for try await pair in group {
                list[pair.index] = pair
            }
            return list.compactMap { $0 }
        }
    }
    
//    func convertImage(_ result: PHPickerResult) async throws -> UIImage {
//        return try await withCheckedThrowingContinuation { continuation in
//            let itemProvider = result.itemProvider
//            if itemProvider.canLoadObject(ofClass: UIImage.self) {
//                itemProvider.loadObject(ofClass: UIImage.self, completionHandler: { image, error in
//                    guard let image = image as? UIImage, error == nil else {
//                        continuation.resume(throwing: MediaError.FailedToConvertImage)
//                        return
//                    }
//
//                    guard let compressed = MediaManager.compressImageWithImageIO(image) else {
//                        print("압축 이미지 데이터 생성 실패")
//                        continuation.resume(throwing: MediaError.FailedToCraeteImageData)
//                        return
//                    }
//                    
//                    continuation.resume(returning: UIImage(cgImage: compressed))
////                    continuation.resume(returning: image)
//                })
//            }
//        }
//    }
//    
//    func dealWithImages(_ results: [PHPickerResult]) async throws -> [UIImage] {
//        return try await withThrowingTaskGroup(of: (Int, UIImage).self) { group in
//            for (index, result) in results.enumerated() {
//                group.addTask {
//                    let image = try await self.convertImage(result)
//                    return (index, image)
//                }
//            }
//            
//            var inOrderImages = Array<UIImage?>(repeating: nil, count: results.count)
//            for try await (index, image) in group {
//                inOrderImages[index] = image
//            }
//            return inOrderImages.compactMap{$0}
//        }
//    }
    
    // MARK: - Video presets & helpers

    enum VideoUploadPreset {
        case dataSaver720    // ~2.0–2.5 Mbps, 720p
        case standard720     // ~4.0–5.0 Mbps, 720p (권장 기본)
        case high1080        // ~6.0–8.0 Mbps, 1080p
    }

    private func bitrate(for preset: VideoUploadPreset) -> Int {
        switch preset {
        case .dataSaver720:  return 2_400_000
        case .standard720:   return 4_500_000
        case .high1080:      return 7_000_000
        }
    }

    private func targetSize(for asset: AVAsset, preset: VideoUploadPreset) -> CGSize {
        guard let track = asset.tracks(withMediaType: .video).first else {
            // 합리적 기본값
            switch preset {
            case .high1080:   return CGSize(width: 1920, height: 1080)
            default:          return CGSize(width: 1280, height: 720)
            }
        }
        let natural = track.naturalSize
        let t = track.preferredTransform
        // 세로/가로 판별 (단순화)
        let isPortrait = (t.a == 0 && abs(t.b) == 1 && abs(t.c) == 1 && t.d == 0)
        let srcW = isPortrait ? natural.height : natural.width
        let srcH = isPortrait ? natural.width  : natural.height
        let aspect = max(srcW, 1) / max(srcH, 1)

        let longSide: CGFloat = (preset == .high1080) ? 1920 : 1280
        // 긴 변 기준으로 맞추고 짝수 픽셀 보장
        var outW: CGFloat
        var outH: CGFloat
        if srcW >= srcH {
            outW = longSide
            outH = (longSide / max(aspect, 0.01))
        } else {
            outH = longSide
            outW = (longSide * max(aspect, 0.01))
        }
        // 짝수 픽셀로 스냅(인코더 호환성)
        outW = floor(outW / 2) * 2
        outH = floor(outH / 2) * 2
        return CGSize(width: max(outW, 2), height: max(outH, 2))
    }

    func convertVideo(_ result: PHPickerResult, preset: VideoUploadPreset = .standard720) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let itemProvider = result.itemProvider
            guard itemProvider.hasRepresentationConforming(toTypeIdentifier: UTType.movie.identifier) else {
                continuation.resume(throwing: NSError(domain: "VideoLoad", code: -2, userInfo: [NSLocalizedDescriptionKey: "지원되지 않는 비디오 타입"]))
                return
            }

            itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { fileURL, error in
                guard let fileURL = fileURL, error == nil else {
                    continuation.resume(throwing: error ?? NSError(domain: "VideoLoad", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video URL 불러오기 실패"]))
                    return
                }

                // 앱 소유 임시 경로로 복사 (원본 임시 URL은 콜백 종료 후 사라질 수 있음)
                let ownedURL: URL
                do {
                    ownedURL = try MediaManager.copyToAppTemporary(from: fileURL)
                } catch {
                    continuation.resume(throwing: NSError(domain: "VideoLoad", code: -3, userInfo: [NSLocalizedDescriptionKey: "임시 파일 복사 실패: \(error.localizedDescription)"]))
                    return
                }

                let asset = AVAsset(url: ownedURL)
                let size = self.targetSize(for: asset, preset: preset)
                let bitrate = self.bitrate(for: preset)

                // NOTE: videomaxKeyFrameInterval 단위(프레임/초)는 라이브러리 문서를 반드시 확인하세요.
                // 여기서는 30fps 기준 "약 2초" 간격을 가정하여 60을 사용합니다.
                let gopIntervalAssumingFrames = 60

                let config = FYVideoCompressor.CompressionConfig(
                    videoBitrate: bitrate,
                    videomaxKeyFrameInterval: gopIntervalAssumingFrames,
                    fps: 30,
                    audioSampleRate: 48_000,     // 일반적 동영상 표준(확실하지 않음: 프레임워크 내부 처리와의 상호작용)
                    audioBitrate: 128_000,
                    fileType: .mp4,              // 확실하지 않음: .mp4가 H.264로 강제되는지/HEVC 허용되는지 라이브러리 문서 확인 필요
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
            }
        }
    }
    
    func dealWithVideos(_ results: [PHPickerResult], preset: VideoUploadPreset = .standard720) async throws -> [URL] {
        return try await withThrowingTaskGroup(of: (Int, URL).self) { group in
            for (index, result) in results.enumerated() {
                group.addTask {
                    let url = try await self.convertVideo(result, preset: preset)
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
    
}
