import AVFoundation
import UIKit
import XCTest
@testable import OutPick

@MainActor
final class ChatVideoPlaybackSessionTests: XCTestCase {
    func testExpiredEntryWithoutAssetDoesNotResolveOrCreatePlayerItem() {
        let unused = ChatVideoPlaybackAsset(url: URL(fileURLWithPath: "/unused"), storagePath: "unused")
        let resolver = SessionPlaybackResolver(asset: unused, now: Date.init)
        let session = ChatVideoPlaybackSession(asset: nil, resolver: resolver)
        XCTAssertEqual(session.state, .expired)
        XCTAssertNil(session.asset)
        XCTAssertNil(session.player.currentItem)
        XCTAssertFalse(session.canSave)
        session.start()
        session.retry()
        XCTAssertEqual(resolver.calls, 0)
        XCTAssertNil(session.player.currentItem)
        session.close()
    }

    func testExpiredVideoScreenShowsNoticeWithoutPlaybackOrSaving() async {
        let unused = ChatVideoPlaybackAsset(url: URL(fileURLWithPath: "/unused"), storagePath: "unused")
        let resolver = SessionPlaybackResolver(asset: unused, now: Date.init)
        let saver = DefaultPhotoLibrarySaver(requestPermission: {
            XCTFail("만료 영상은 Photos 권한을 요청하면 안 된다")
            return false
        })
        let viewer = ChatVideoPlayerViewController(playbackAsset: nil, videoResolver: resolver, photoLibrarySaver: saver)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        // AVKit overlay는 실제 presentation이 완료된 뒤 화면 계층에 연결된다.
        await withCheckedContinuation { continuation in
            host.present(viewer, animated: false) { continuation.resume() }
        }
        func descendants(_ view: UIView) -> [UIView] {
            view.subviews + view.subviews.flatMap(descendants)
        }
        let views = descendants(viewer.view)
        XCTAssertTrue(views.compactMap { $0 as? UILabel }.contains { $0.text == "미디어 저장 기간이 만료되었어요." })
        let saveButtons = views.compactMap { $0 as? UIButton }.filter { $0.accessibilityIdentifier == "chatVideoSaveButton" }
        XCTAssertFalse(saveButtons.isEmpty)
        for button in saveButtons {
            XCTAssertFalse(button.isEnabled)
            button.sendActions(for: .touchUpInside)
        }
        XCTAssertEqual(resolver.calls, 0)
        XCTAssertEqual(resolver.saveCalls, 0)
        await withCheckedContinuation { continuation in
            host.dismiss(animated: false) { continuation.resume() }
        }
        XCTAssertEqual(resolver.calls, 0)
        XCTAssertEqual(resolver.saveCalls, 0)
    }

    func testBackgroundSeekCompletesAndPreservesPausedPosition() async throws {
        let url = try await syntheticVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = ChatVideoPlaybackAsset(url: url, storagePath: "local")
        let resolver = SessionPlaybackResolver(asset: asset, now: Date.init)
        let session = ChatVideoPlaybackSession(asset: asset, resolver: resolver)
        defer { session.close() }
        await waitUntil { session.player.currentItem?.status == .readyToPlay }
        let player = session.player
        let success = await withCheckedContinuation { continuation in
            DispatchQueue(label: "qa.avkit.seekQueue").async {
                XCTAssertFalse(Thread.isMainThread)
                player.seek(to: CMTime(seconds: 2, preferredTimescale: 600),
                            toleranceBefore: .zero, toleranceAfter: .zero) {
                    continuation.resume(returning: $0)
                }
            }
        }
        XCTAssertTrue(success)
        XCTAssertEqual(player.currentTime().seconds, 2, accuracy: 0.25)
        XCTAssertEqual(player.rate, 0)
        XCTAssertEqual(resolver.calls, 0)
    }

    func testBackgroundSeekRejectsExpiredMediaAndCompletesOnce() async throws {
        let url = try await syntheticVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        var now = Date()
        let resource = resource(expiry: now.addingTimeInterval(600))
        let asset = ChatVideoPlaybackAsset(url: url, storagePath: resource.path, resource: resource)
        let resolver = SessionPlaybackResolver(asset: asset, now: { now })
        let session = ChatVideoPlaybackSession(asset: asset, resolver: resolver, now: { now })
        defer { session.close() }
        await waitUntil { session.player.currentItem?.status == .readyToPlay }
        now = resource.mediaExpiresAt
        let completed = expectation(description: "만료 탐색 콜백")
        completed.assertForOverFulfill = true
        let player = session.player
        DispatchQueue(label: "qa.avkit.seekQueue").async {
            player.seek(to: CMTime(seconds: 2, preferredTimescale: 600)) { success in
                XCTAssertFalse(success)
                completed.fulfill()
            }
        }
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(session.state, .expired)
        XCTAssertNil(player.currentItem)
        XCTAssertEqual(resolver.calls, 0)
    }

    func testPausedURLExpiryRenewsOnResumeAndPreservesPosition() async throws {
        try await verifyRenewal(seekWhilePaused: false)
    }

    func testSeekWithExpiredURLPreservesTargetAndPausedState() async throws {
        try await verifyRenewal(seekWhilePaused: true)
    }

    private func verifyRenewal(seekWhilePaused: Bool) async throws {
        let url = try await syntheticVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        var now = Date()
        let resource = resource(expiry: now.addingTimeInterval(600))
        let initial = ChatVideoPlaybackAsset(url: url, storagePath: resource.path, resource: resource,
                                             urlExpiresAt: now.addingTimeInterval(1))
        let resolver = SessionPlaybackResolver(asset: initial, now: { now })
        let session = ChatVideoPlaybackSession(asset: initial, resolver: resolver, now: { now })
        defer { session.close() }
        await waitUntil { session.player.currentItem?.status == .readyToPlay }
        let success = await withCheckedContinuation { continuation in
            session.player.seek(to: CMTime(seconds: 1, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) {
                continuation.resume(returning: $0)
            }
        }
        XCTAssertTrue(success)
        session.player.pause()
        now = now.addingTimeInterval(2)
        session.checkBoundaries()
        XCTAssertEqual(resolver.calls, 0)
        if seekWhilePaused {
            let completed = expectation(description: "URL 갱신을 시작한 탐색 콜백")
            completed.assertForOverFulfill = true
            let player = session.player
            DispatchQueue(label: "qa.avkit.seekQueue").async {
                player.seek(to: CMTime(seconds: 2, preferredTimescale: 600), completionHandler: {
                    XCTAssertFalse($0)
                    completed.fulfill()
                })
            }
            await fulfillment(of: [completed], timeout: 3)
        } else {
            session.start()
        }
        await waitUntil { resolver.calls == 1 && session.state == .ready }
        let expectedTime: Double = seekWhilePaused ? 2 : 1
        XCTAssertEqual(session.player.currentTime().seconds, expectedTime, accuracy: 0.25)
        XCTAssertEqual(session.player.rate, seekWhilePaused ? 0 : 1)
        XCTAssertEqual(session.asset?.resource?.mediaExpiresAt, resource.mediaExpiresAt)
        XCTAssertEqual(resolver.calls, 1)
    }

    func testRefreshFailureWaitsForManualRetry() async throws {
        let url = try await syntheticVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        var now = Date()
        let resource = resource(expiry: now.addingTimeInterval(600))
        let asset = ChatVideoPlaybackAsset(url: url, storagePath: resource.path, resource: resource,
                                          urlExpiresAt: now.addingTimeInterval(1))
        let resolver = SessionPlaybackResolver(asset: asset, now: { now })
        resolver.shouldFail = true
        let session = ChatVideoPlaybackSession(asset: asset, resolver: resolver, now: { now })
        defer { session.close() }
        now = now.addingTimeInterval(2)
        session.start()
        await waitUntil { session.state == .failed(.temporarilyUnavailable) }
        session.checkBoundaries()
        session.start()
        XCTAssertEqual(resolver.calls, 1)
        resolver.shouldFail = false
        session.retry()
        await waitUntil { resolver.calls == 2 && session.state == .ready }
    }

    func testMediaExpiryClearsPlayerAndRejectsLateRenewal() async throws {
        let url = try await syntheticVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        var now = Date()
        let resource = resource(expiry: now.addingTimeInterval(3))
        let asset = ChatVideoPlaybackAsset(url: url, storagePath: resource.path, resource: resource,
                                          urlExpiresAt: now.addingTimeInterval(1))
        let resolver = SessionPlaybackResolver(asset: asset, now: { now })
        resolver.delayed = true
        let session = ChatVideoPlaybackSession(asset: asset, resolver: resolver, now: { now })
        now = now.addingTimeInterval(2)
        session.start()
        await waitUntil { resolver.pending != nil }
        now = resource.mediaExpiresAt
        session.checkBoundaries()
        XCTAssertEqual(session.state, .expired)
        XCTAssertNil(session.player.currentItem)
        XCTAssertNil(session.asset)
        XCTAssertFalse(session.canSave)
        resolver.finish()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(session.state, .expired)
        XCTAssertNil(session.player.currentItem)
        session.retry()
        XCTAssertEqual(resolver.calls, 1)
    }

    private func resource(expiry: Date) -> ChatVideoPlaybackResource {
        ChatVideoPlaybackResource(roomID: "room", messageID: "message", attachmentID: "attachment",
                                  path: "gs://ready/video", generation: "123", mediaExpiresAt: expiry)!
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition())
    }

    private func syntheticVideo() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ExpiryPlayback-\(UUID()).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
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
        for frame in 0..<10 {
            for _ in 0..<200 where !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            XCTAssertTrue(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 2)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }
}

@MainActor
private final class SessionPlaybackResolver: ChatVideoPlaybackResolving {
    var asset: ChatVideoPlaybackAsset
    let now: () -> Date
    var calls = 0
    var saveCalls = 0
    var shouldFail = false
    var delayed = false
    var pending: CheckedContinuation<Void, Never>?
    init(asset: ChatVideoPlaybackAsset, now: @escaping () -> Date) { self.asset = asset; self.now = now }
    func playbackAsset(for resource: ChatVideoPlaybackResource, forceRefresh: Bool) async throws -> ChatVideoPlaybackAsset {
        calls += 1
        if delayed { await withCheckedContinuation { pending = $0 } }
        if shouldFail { throw ChatVideoPlaybackError.temporarilyUnavailable }
        var next = asset
        next.urlExpiresAt = min(now().addingTimeInterval(60), resource.mediaExpiresAt)
        return next
    }
    func finish() { let saved = pending; pending = nil; saved?.resume() }
    func playbackAsset(forPath path: String) async throws -> ChatVideoPlaybackAsset {
        calls += 1
        return asset
    }
    func acquireFileForSaving(_ asset: ChatVideoPlaybackAsset) async throws -> ChatOriginalFileLease {
        saveCalls += 1
        throw ChatMediaPreviewError.missingSaveSource
    }
}
