import XCTest
import UIKit
import Kingfisher
@testable import OutPick

@MainActor
final class ImageViewerStateTests: XCTestCase {
    private func descendants<T: UIView>(_ view: UIView, _: T.Type) -> [T] {
        view.subviews.flatMap { child in
            (child as? T).map { [$0] } ?? []
        } + view.subviews.flatMap { descendants($0, T.self) }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition())
    }

    private func makeViewer(image: UIImage? = nil, path: String? = nil, loader: SimpleImageViewerVC.LoadImageProvider? = nil, saver: PhotoLibrarySaving) -> SimpleImageViewerVC {
        let viewer = SimpleImageViewerVC(
            pages: [.init(initialImage: image, thumbnailPath: nil, originalPath: path)],
            startIndex: 0, cachedImageProvider: nil, loadImageProvider: loader,
            photoLibrarySaver: saver
        )
        viewer.loadViewIfNeeded()
        viewer.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewer.view.layoutIfNeeded()
        return viewer
    }

    func testLocalOnlyImageDoesNotFailAndDuplicateSaveIsBlocked() async throws {
        let saver = ViewerSaverSpy()
        let image = UIImage(systemName: "star")!
        let viewer = makeViewer(image: image, saver: saver)
        let chrome = try XCTUnwrap(descendants(viewer.view, ImageViewerChromeView.self).first)
        chrome.saveButton.sendActions(for: .touchUpInside)
        chrome.saveButton.sendActions(for: .touchUpInside)
        await waitUntil { saver.images.count == 1 }
        XCTAssertTrue(saver.images[0] === image)
        XCTAssertFalse(chrome.saveButton.isEnabled)
        saver.finish()
        await waitUntil { chrome.saveButton.isEnabled }
        XCTAssertFalse(descendants(viewer.view, UIButton.self).contains { !$0.isHidden && $0.currentTitle == "불러오지 못했어요 · 다시 시도" })
    }

    func testSaveFailureRestoresButtonAndAllowsRetry() async throws {
        let saver = ViewerSaverSpy()
        let viewer = makeViewer(image: UIImage(systemName: "star"), saver: saver)
        let chrome = try XCTUnwrap(descendants(viewer.view, ImageViewerChromeView.self).first)
        chrome.saveButton.sendActions(for: .touchUpInside)
        await waitUntil { saver.images.count == 1 }
        saver.finish(error: PhotoLibrarySaveError.saveFailed)
        await waitUntil { chrome.saveButton.isEnabled }
        chrome.saveButton.sendActions(for: .touchUpInside)
        await waitUntil { saver.images.count == 2 }
        saver.finish()
        await waitUntil { chrome.saveButton.isEnabled }
    }

    func testLoadingFailurePreservesPreviewAndRetryReplacesIt() async throws {
        let loader = ViewerLoaderSpy()
        let preview = UIImage(systemName: "star")!
        let original = UIImage(systemName: "heart")!
        let viewer = makeViewer(image: preview, path: "original", loader: { _, _ in await loader.load() }, saver: ViewerSaverSpy())
        await waitUntil { loader.pending.count == 1 }
        loader.finish(nil)
        let retry = try XCTUnwrap(descendants(viewer.view, UIButton.self).first { $0.currentTitle == "불러오는 중…" || $0.currentTitle == "불러오지 못했어요 · 다시 시도" })
        await waitUntil { retry.isEnabled }
        XCTAssertTrue(descendants(viewer.view, AnimatedImageView.self).first?.image === preview)
        retry.sendActions(for: .touchUpInside)
        await waitUntil { loader.pending.count == 1 }
        loader.finish(original)
        await waitUntil { descendants(viewer.view, AnimatedImageView.self).first?.image === original }
        XCTAssertTrue(retry.isHidden)
    }

    func testLateResponseAfterCloseDoesNotReplaceImage() async throws {
        let loader = ViewerLoaderSpy()
        let preview = UIImage(systemName: "star")!
        let viewer = makeViewer(image: preview, path: "original", loader: { _, _ in await loader.load() }, saver: ViewerSaverSpy())
        await waitUntil { loader.pending.count == 1 }
        let chrome = try XCTUnwrap(descendants(viewer.view, ImageViewerChromeView.self).first)
        chrome.closeButton.sendActions(for: .touchUpInside)
        loader.finish(UIImage(systemName: "heart"))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(descendants(viewer.view, AnimatedImageView.self).first?.image === preview)
    }

    func testSupersededLoadCannotOverwriteRetry() async throws {
        let loader = ViewerLoaderSpy()
        let viewer = makeViewer(path: "original", loader: { _, _ in await loader.load() }, saver: ViewerSaverSpy())
        await waitUntil { loader.pending.count == 1 }
        viewer.perform(NSSelectorFromString("retryCurrentPage"))
        await waitUntil { loader.pending.count == 2 }
        let old = loader.pending.removeFirst()
        let freshImage = UIImage(systemName: "heart")!
        loader.finish(freshImage)
        await waitUntil { descendants(viewer.view, AnimatedImageView.self).first?.image === freshImage }
        old.resume(returning: UIImage(systemName: "star"))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(descendants(viewer.view, AnimatedImageView.self).first?.image === freshImage)
    }

    func testSaveKeepsTappedPageWhilePaging() async throws {
        let saver = ViewerSaverSpy()
        let first = UIImage(systemName: "star")!
        let viewer = SimpleImageViewerVC(pages: [
            .init(initialImage: first, thumbnailPath: nil, originalPath: nil),
            .init(initialImage: UIImage(systemName: "heart"), thumbnailPath: nil, originalPath: nil)
        ], startIndex: 0, cachedImageProvider: nil, loadImageProvider: nil, photoLibrarySaver: saver)
        viewer.loadViewIfNeeded()
        viewer.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewer.view.layoutIfNeeded()
        let chrome = try XCTUnwrap(descendants(viewer.view, ImageViewerChromeView.self).first)
        chrome.saveButton.sendActions(for: .touchUpInside)
        let pager = try XCTUnwrap(viewer.view.subviews.compactMap { $0 as? UIScrollView }.first)
        pager.setContentOffset(CGPoint(x: 390, y: 0), animated: false)
        await waitUntil { saver.images.count == 1 }
        XCTAssertTrue(saver.images[0] === first)
        saver.finish()
        await waitUntil { chrome.saveButton.isEnabled }
    }

    func testChromeLayoutAndRender() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let host = UIViewController()
        window.rootViewController = host
        let chrome = ImageViewerChromeView(hasReport: true)
        chrome.frame = window.bounds
        host.view.addSubview(chrome)
        chrome.render(index: 0, count: 31, saving: false)
        window.isHidden = false
        window.layoutIfNeeded()
        chrome.layoutIfNeeded()
        let counter = try XCTUnwrap(descendants(chrome, UILabel.self).first { $0.text == "01 / 31" })
        XCTAssertEqual(counter.convert(counter.bounds, to: chrome).midX, chrome.bounds.midX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(chrome.closeButton.bounds.height, 44)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { context in
            window.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "공용 이미지 뷰어 컨트롤"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
    }
}

@MainActor
private final class ViewerLoaderSpy {
    var pending: [CheckedContinuation<UIImage?, Never>] = []
    func load() async -> UIImage? { await withCheckedContinuation { pending.append($0) } }
    func finish(_ image: UIImage?) { pending.removeFirst().resume(returning: image) }
}

private final class ViewerSaverSpy: PhotoLibrarySaving {
    @MainActor var images: [UIImage] = []
    @MainActor private var pending: CheckedContinuation<Void, Error>?
    @MainActor func saveImage(_ image: UIImage) async throws {
        images.append(image)
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func saveVideo(fileURL: URL) async throws { }
    @MainActor func finish(error: Error? = nil) {
        let continuation = pending
        pending = nil
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }
}
