import XCTest
import UIKit
@testable import OutPick

@MainActor
final class ImageViewerOriginalFileTests: XCTestCase {
    private func descendants<T: UIView>(_ view: UIView, _: T.Type) -> [T] {
        view.subviews.flatMap { ($0 as? T).map { [$0] } ?? [] } + view.subviews.flatMap { descendants($0, T.self) }
    }
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(condition())
    }
    private func makeViewer(_ loader: OriginalViewerLoader, saver: OriginalViewerSaver, pages: [ImageViewerPage]? = nil) -> SimpleImageViewerVC {
        let viewer = SimpleImageViewerVC(
            pages: pages ?? [.init(initialImage: UIImage(systemName: "star"), thumbnailPath: "preview", originalPath: "original")],
            startIndex: 0, cachedImageProvider: nil, loadImageProvider: nil,
            photoLibrarySaver: saver, originalFiles: loader
        )
        viewer.loadViewIfNeeded()
        viewer.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewer.view.layoutIfNeeded()
        return viewer
    }

    func testSaveUsesOriginalFileAndFailureAllowsExplicitRetry() async throws {
        let loader = try OriginalViewerLoader()
        defer { loader.clean() }
        let saver = OriginalViewerSaver()
        let viewer = makeViewer(loader, saver: saver)
        viewer.perform(NSSelectorFromString("saveTapped"))
        await waitUntil { loader.saves.count == 1 }
        loader.finishSaving()
        await waitUntil { saver.files.count == 1 }
        XCTAssertEqual(saver.files.first, loader.url)
        XCTAssertEqual(saver.imageSaves, 0)
        saver.finish(error: PhotoLibrarySaveError.permissionDenied)
        let chrome = try XCTUnwrap(descendants(viewer.view, ImageViewerChromeView.self).first)
        await waitUntil { chrome.saveButton.isEnabled }
        chrome.saveButton.sendActions(for: .touchUpInside)
        await waitUntil { loader.saves.count == 1 }
        loader.finishSaving()
        await waitUntil { saver.files.count == 2 }
        saver.finish()
        await waitUntil { chrome.saveButton.isEnabled }
        chrome.closeButton.sendActions(for: .touchUpInside)
    }

    func testCloseDuringPreparationRejectsLateSaveAndReleasesFile() async throws {
        let loader = try OriginalViewerLoader()
        defer { loader.clean() }
        let saver = OriginalViewerSaver()
        let viewer = makeViewer(loader, saver: saver)
        viewer.perform(NSSelectorFromString("saveTapped"))
        await waitUntil { loader.saves.count == 1 }
        viewer.perform(NSSelectorFromString("closeTapped"))
        loader.finishSaving()
        await waitUntil { loader.cancelledSaves == 1 }
        XCTAssertTrue(saver.files.isEmpty)
        XCTAssertFalse(descendants(viewer.view, UILabel.self).contains { $0.text == "저장 완료" || $0.text == "저장 실패" })
    }

    func testCloseAfterSubmissionSuppressesLateCompletionUI() async throws {
        let loader = try OriginalViewerLoader()
        defer { loader.clean() }
        let saver = OriginalViewerSaver()
        let viewer = makeViewer(loader, saver: saver)
        viewer.perform(NSSelectorFromString("saveTapped"))
        await waitUntil { loader.saves.count == 1 }
        loader.finishSaving()
        await waitUntil { saver.files.count == 1 }
        viewer.perform(NSSelectorFromString("closeTapped"))
        saver.finish()
        for _ in 0..<50 { await Task.yield() }
        XCTAssertFalse(descendants(viewer.view, UILabel.self).contains { $0.text == "저장 완료" || $0.text == "저장 실패" })
    }

    func testAdjacentPolicyDoesNotSkipGIFOrVideoPosition() {
        let pages: [ImageViewerPage] = [
            .init(thumbnailPath: nil, originalPath: "a.jpg", attachmentPosition: 0),
            .init(thumbnailPath: nil, originalPath: "b.gif", isAnimated: true, attachmentPosition: 1),
            .init(thumbnailPath: nil, originalPath: "c.jpg", attachmentPosition: 2),
            .init(thumbnailPath: nil, originalPath: "e.jpg", attachmentPosition: 4)
        ]
        XCTAssertEqual(ImageViewerOriginalPolicy.indices(pages: pages, current: 0), [0])
        XCTAssertEqual(ImageViewerOriginalPolicy.indices(pages: pages, current: 1), [0, 1, 2])
        XCTAssertEqual(ImageViewerOriginalPolicy.indices(pages: pages, current: 2), [2])
        XCTAssertEqual(ImageViewerOriginalPolicy.indices(pages: pages, current: 3), [3])
    }

    func testActualViewerRequestsOnlyCurrentAndAdjacentStaticPages() async throws {
        let loader = try OriginalViewerLoader()
        defer { loader.clean() }
        let pages = (0..<5).map { (index: Int) in ImageViewerPage(thumbnailPath: nil, originalPath: "\(index).jpg", attachmentPosition: index) }
        let viewer = makeViewer(loader, saver: OriginalViewerSaver(), pages: pages)
        await waitUntil { loader.viewPaths.count == 2 }
        XCTAssertEqual(Set(loader.viewPaths), ["0.jpg", "1.jpg"])
        let pager = try XCTUnwrap(viewer.view.subviews.compactMap { $0 as? UIScrollView }.first)
        pager.setContentOffset(CGPoint(x: pager.bounds.width * 3, y: 0), animated: false)
        viewer.scrollViewDidScroll(pager)
        await waitUntil { loader.viewPaths.count == 5 }
        XCTAssertEqual(Set(loader.viewPaths.suffix(3)), ["2.jpg", "3.jpg", "4.jpg"])
        viewer.perform(NSSelectorFromString("closeTapped"))
    }

    func testAdjacentDownloadsWaitForCurrentFileAndThenStartTogether() async throws {
        let loader = try OriginalViewerLoader()
        loader.holdViews = true
        defer { loader.finishViews(); loader.clean() }
        let pages = (0..<5).map { ImageViewerPage(thumbnailPath: nil, originalPath: "\($0).jpg") }
        let viewer = makeViewer(loader, saver: OriginalViewerSaver(), pages: pages)
        await waitUntil { loader.viewPaths == ["0.jpg"] }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(loader.viewPaths, ["0.jpg"])
        let pager = try XCTUnwrap(viewer.view.subviews.compactMap { $0 as? UIScrollView }.first)
        pager.setContentOffset(CGPoint(x: pager.bounds.width * 3, y: 0), animated: false)
        viewer.scrollViewDidScroll(pager)
        await waitUntil { loader.viewPaths == ["0.jpg", "3.jpg"] }
        loader.finishView("0.jpg")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(loader.viewPaths, ["0.jpg", "3.jpg"])
        loader.finishView("3.jpg")
        await waitUntil { loader.viewPaths.count == 4 }
        XCTAssertEqual(Set(loader.viewPaths.suffix(2)), ["2.jpg", "4.jpg"])
        viewer.perform(NSSelectorFromString("closeTapped"))
    }

    func testClosingBeforeCurrentFileReturnsDoesNotStartAdjacent() async throws {
        let loader = try OriginalViewerLoader()
        loader.holdViews = true
        defer { loader.finishViews(); loader.clean() }
        let pages = (0..<3).map { ImageViewerPage(thumbnailPath: nil, originalPath: "\($0).jpg") }
        let viewer = makeViewer(loader, saver: OriginalViewerSaver(), pages: pages)
        await waitUntil { loader.viewPaths == ["0.jpg"] }
        viewer.perform(NSSelectorFromString("closeTapped"))
        loader.finishViews()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(loader.viewPaths, ["0.jpg"])
    }
}

@MainActor
private final class OriginalViewerLoader: ChatOriginalFileLoading {
    let url: URL
    var viewPaths: [String] = []
    var saves: [CheckedContinuation<Void, Never>] = []
    var cancelledSaves = 0
    var holdViews = false
    private var pendingViews: [String: CheckedContinuation<Void, Never>] = [:]
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("OriginalViewer-\(UUID().uuidString).png")
        try UIImage(systemName: "heart")!.pngData()!.write(to: url)
    }
    func acquireOriginal(_ resource: ChatOriginalResource, purpose: ChatOriginalPurpose) async throws -> ChatOriginalFileLease {
        if case .saving = purpose {
            await withCheckedContinuation { saves.append($0) }
            if Task.isCancelled { cancelledSaves += 1 }
        } else {
            viewPaths.append(resource.path)
            if holdViews { await withCheckedContinuation { pendingViews[resource.path] = $0 } }
            try Task.checkCancellation()
        }
        return ChatOriginalFileLease(fileURL: url, isValid: { true }, release: {})
    }
    func cachedOriginal(_ resource: ChatOriginalResource) async throws -> ChatOriginalFileLease? { nil }
    func removeOriginal(path: String) async {}
    nonisolated func invalidateSession() {}
    func finishSaving() { saves.removeFirst().resume() }
    func finishView(_ path: String) { pendingViews.removeValue(forKey: path)?.resume() }
    func finishViews() {
        let pending = pendingViews
        pendingViews.removeAll()
        pending.values.forEach { $0.resume() }
    }
    func clean() { try? FileManager.default.removeItem(at: url) }
}

@MainActor
private final class OriginalViewerSaver: PhotoLibrarySaving {
    var files: [URL] = []
    var imageSaves = 0
    private var pending: CheckedContinuation<Void, Error>?
    func saveOriginal(_ lease: ChatOriginalFileLease, isVideo: Bool) async throws {
        files.append(lease.fileURL)
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func saveImage(_ image: UIImage) async throws { imageSaves += 1 }
    func saveVideo(fileURL: URL) async throws {}
    func finish(error: Error? = nil) {
        let continuation = pending; pending = nil
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }
}
