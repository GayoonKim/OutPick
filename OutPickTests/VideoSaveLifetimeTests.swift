import AVKit
import XCTest
@testable import OutPick

@MainActor
final class VideoSaveLifetimeTests: XCTestCase {
    func testChatCloseDuringPreparation() async throws { try await verify(overlay: false, submitted: false, failure: false) }
    func testOverlayCloseDuringPreparation() async throws { try await verify(overlay: true, submitted: false, failure: false) }
    func testChatCloseAfterSubmissionSuccess() async throws { try await verify(overlay: false, submitted: true, failure: false) }
    func testOverlayCloseAfterSubmissionSuccess() async throws { try await verify(overlay: true, submitted: true, failure: false) }
    func testChatCloseAfterSubmissionFailure() async throws { try await verify(overlay: false, submitted: true, failure: true) }
    func testOverlayCloseAfterSubmissionFailure() async throws { try await verify(overlay: true, submitted: true, failure: true) }

    private func descendants<T: UIView>(_ view: UIView, _ type: T.Type) -> [T] {
        view.subviews.compactMap { $0 as? T } + view.subviews.flatMap { descendants($0, type) }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(condition())
    }

    private func verify(overlay: Bool, submitted: Bool, failure: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VideoLifetime-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("original.bin")
        let bytes = Data([0, 0, 0, 20]) + Data("ftypmp42".utf8) + Data([0, 0, 0, 0]) + Data("mp42".utf8)
        try bytes.write(to: source)
        let playbackRelease = VideoReleaseCounter()
        let sourceLease = ChatOriginalFileLease(fileURL: source, isValid: { true }, release: { playbackRelease.increment() })
        let asset = try await DefaultChatVideoPlaybackResolver.cachedPlaybackAsset(lease: sourceLease, path: "fixture")
        let saving = root.appendingPathComponent("saving.mp4")
        try bytes.write(to: saving)
        let saveRelease = VideoReleaseCounter()
        let resolver = DelayedVideoResolver(url: saving, released: saveRelease)
        let saver = DelayedVideoSaver()
        defer { resolver.finish(); saver.finish(failure: false) }
        let viewer: UIViewController = overlay
            ? VideoPlayerOverlayVC(playbackAsset: asset, videoResolver: resolver, photoLibrarySaver: saver)
            : ChatVideoPlayerViewController(playbackAsset: asset, videoResolver: resolver, photoLibrarySaver: saver)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        await withCheckedContinuation { continuation in
            host.present(viewer, animated: false) { continuation.resume() }
        }
        let player = try XCTUnwrap(viewer.children.compactMap { $0 as? AVPlayerViewController }.first)
        if overlay {
            viewer.perform(NSSelectorFromString("saveTapped"))
        } else {
            let content = try XCTUnwrap(player.contentOverlayView)
            let button = try XCTUnwrap(content.subviews.compactMap { $0 as? UIButton }.first)
            button.sendActions(for: .touchUpInside)
        }
        await waitUntil { resolver.pending != nil }
        if submitted {
            resolver.finish()
            await waitUntil { saver.pending != nil }
            XCTAssertTrue(FileManager.default.fileExists(atPath: saving.path))
        }
        // 실제 UIKit dismiss가 viewDidDisappear의 닫기 수명 처리를 호출한다.
        await withCheckedContinuation { continuation in
            host.dismiss(animated: false) { continuation.resume() }
        }
        await waitUntil { playbackRelease.count == 1 }
        XCTAssertNil(player.player)
        XCTAssertFalse(FileManager.default.fileExists(atPath: asset.url.path))
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        if submitted {
            // Photos 완료 전에는 제출된 파일을 제거하지 않는다.
            XCTAssertEqual(saveRelease.count, 0)
            XCTAssertTrue(FileManager.default.fileExists(atPath: saving.path))
            saver.finish(failure: failure)
        } else {
            resolver.finish()
        }
        await waitUntil { saveRelease.count == 1 }
        XCTAssertEqual(saver.calls, submitted ? 1 : 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saving.path))
        XCTAssertFalse(descendants(viewer.view, UILabel.self).contains { ["저장 완료", "저장 실패"].contains($0.text ?? "") })
        XCTAssertNil(viewer.presentedViewController)
        XCTAssertEqual(playbackRelease.count, 1)
    }
}

private final class VideoReleaseCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func increment() { lock.lock(); value += 1; lock.unlock() }
}

@MainActor
private final class DelayedVideoResolver: ChatVideoPlaybackResolving {
    let url: URL
    let released: VideoReleaseCounter
    var pending: CheckedContinuation<Void, Never>?
    init(url: URL, released: VideoReleaseCounter) { self.url = url; self.released = released }
    func acquireFileForSaving(_ asset: ChatVideoPlaybackAsset) async throws -> ChatOriginalFileLease {
        await withCheckedContinuation { pending = $0 }
        // 취소를 무시하고 늦게 파일을 반환하는 의존성도 화면이 안전하게 처리해야 한다.
        let url = url, released = released
        return ChatOriginalFileLease(fileURL: url, isValid: { true }, release: {
            try? FileManager.default.removeItem(at: url)
            released.increment()
        })
    }
    func finish() { let p = pending; pending = nil; p?.resume() }
    func playbackAsset(forPath path: String) async throws -> ChatVideoPlaybackAsset { throw PhotoLibrarySaveError.saveFailed }
    func localFileURLForSaving(localURL: URL?, storagePath: String?, onProgress: @escaping (Double) -> Void) async throws -> URL { url }
}

@MainActor
private final class DelayedVideoSaver: PhotoLibrarySaving {
    var pending: CheckedContinuation<Void, Error>?
    var calls = 0
    func saveOriginal(_ lease: ChatOriginalFileLease, isVideo: Bool) async throws {
        calls += 1
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func finish(failure: Bool) {
        let p = pending; pending = nil
        if failure { p?.resume(throwing: PhotoLibrarySaveError.saveFailed) } else { p?.resume() }
    }
    func saveImage(_ image: UIImage) async throws { XCTFail("원본 파일 저장만 사용해야 한다") }
    func saveVideo(fileURL: URL) async throws { XCTFail("원본 lease 저장만 사용해야 한다") }
}
