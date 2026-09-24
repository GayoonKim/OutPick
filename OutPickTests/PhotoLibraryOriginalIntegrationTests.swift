import Photos
import AVFoundation
import UIKit
import XCTest
@testable import OutPick

/// 사용자 기기/사진을 사용하지 않는다. 미리 photos-add 권한을 준 Simulator에서만 실행한다.
@MainActor
final class PhotoLibraryOriginalIntegrationTests: XCTestCase {
    func testSavesSyntheticMP4FromBinFileThroughRealPhotos() async throws {
        try await saveSyntheticVideo(type: .mp4)
    }

    func testSavesSyntheticMOVFromBinFileThroughRealPhotos() async throws {
        try await saveSyntheticVideo(type: .mov)
    }

    private func saveSyntheticVideo(type: AVFileType) async throws {
        #if targetEnvironment(simulator)
        guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized else {
            throw XCTSkip("Simulator photos-add 권한 필요")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VideoPhotos-\(UUID()).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: type)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                                         kCVPixelBufferWidthKey as String: 16, kCVPixelBufferHeightKey as String: 16])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32ARGB, nil, &buffer), kCVReturnSuccess)
        let pixel = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixel, [])
        memset(CVPixelBufferGetBaseAddress(pixel), 0, CVPixelBufferGetDataSize(pixel))
        CVPixelBufferUnlockBaseAddress(pixel, [])
        for frame in 0..<3 {
            for _ in 0..<200 where !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            XCTAssertTrue(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 2)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        let bytes = try Data(contentsOf: url)
        let lease = ChatOriginalFileLease(fileURL: url, isValid: { true }, release: {})
        let playback = try await DefaultChatVideoPlaybackResolver.cachedPlaybackAsset(lease: lease, path: "synthetic-video")
        let playable = try await AVURLAsset(url: playback.url).load(.isPlayable)
        XCTAssertTrue(playable)
        XCTAssertEqual(playback.url.pathExtension, type == .mov ? "mov" : "mp4")
        try await DefaultPhotoLibrarySaver().saveOriginal(lease, isVideo: true)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        await playback.fileLease?.release()
        XCTAssertFalse(FileManager.default.fileExists(atPath: playback.url.path))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        #else
        throw XCTSkip("Simulator 전용")
        #endif
    }

    func testSavesSyntheticJPEGFromBinFileThroughRealPhotos() async throws {
        #if targetEnvironment(simulator)
        guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized else {
            throw XCTSkip("Simulator의 photos-add 권한을 먼저 부여해야 합니다.")
        }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OriginalPhotosIntegration-\(UUID().uuidString).bin")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let lease = ChatOriginalFileLease(fileURL: url, isValid: { true }, release: {})
        try await DefaultPhotoLibrarySaver().saveOriginal(lease, isVideo: false)
        XCTAssertEqual(try Data(contentsOf: url), data)
        await lease.release()
        #else
        throw XCTSkip("합성 Photos 저장 통합 테스트는 Simulator 전용입니다.")
        #endif
    }
}
