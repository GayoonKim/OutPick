import XCTest
import UIKit
@testable import OutPick

private final class SpinnerTraceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ImageCacheMetrics.Event] = []
    var events: [ImageCacheMetrics.Event] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
    func append(_ event: ImageCacheMetrics.Event) {
        lock.lock()
        stored.append(event)
        lock.unlock()
    }
}

@MainActor
final class ChatImagePreviewContinuityTests: XCTestCase {
    func testSpinnerTracePairsActualStartWithImageAndReuse() {
        let recorder = SpinnerTraceRecorder()
        let cell = ChatImagePreviewCell(frame: .zero)
        cell.diagnostics = ImageCacheMetrics(enabled: true, sink: recorder.append)
        cell.configure(with: item(path: "chat/trace.jpg"), image: nil)
        cell.render(.loading, memoryCacheHit: false)
        cell.render(.loading, memoryCacheHit: false)
        cell.render(.image(UIImage()))
        cell.render(.loading, memoryCacheHit: false)
        let spans = recorder.events.filter { $0.stage == "chatPreview.spinner" }
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans.first?.id, spans.last?.id)
        XCTAssertEqual(spans.last?.outcome, "image")
        XCTAssertTrue(recorder.events.contains { $0.stage == "chatPreview.spinnerState" && $0.outcome == "memoryMiss_offWindow" && $0.parent == spans.first?.id })
        cell.prepareForReuse()
        cell.configure(with: item(path: "chat/new.jpg"), image: nil)
        cell.render(.loading, memoryCacheHit: false)
        cell.prepareForReuse()
        XCTAssertEqual(recorder.events.last { $0.stage == "chatPreview.spinner" }?.outcome, "reset")
    }

    func testIdentitySurvivesServerPathAndHashChangeButSeparatesAttachments() {
        let local = item(path: "file:///tmp/local.jpg")
        let remote = item(path: "chat/remote.jpg", hash: "server-hash")
        XCTAssertEqual(local.id, remote.id)
        XCTAssertNotEqual(local.id, item(path: "chat/remote.jpg", index: 1).id)
        XCTAssertNotEqual(local.id, item(path: "chat/remote.jpg", messageID: "other").id)
    }

    func testDisplayedImageSurvivesConfirmationAndReuseClearsIt() throws {
        let cell = ChatImagePreviewCell(frame: .zero)
        let photo = UIImage()
        cell.configure(with: item(path: "file:///tmp/local.jpg"), image: photo)
        cell.configure(with: item(path: "chat/remote.jpg"), image: nil)
        XCTAssertTrue(try imageView(in: cell).image === photo)
        cell.render(.loading)
        XCTAssertTrue(try imageView(in: cell).image === photo)
        cell.render(.idle)
        XCTAssertTrue(try imageView(in: cell).image === photo)
        cell.prepareForReuse()
        XCTAssertNil(try imageView(in: cell).image)
        cell.configure(with: item(path: "chat/other.jpg", messageID: "other"), image: nil)
        XCTAssertNil(try imageView(in: cell).image)
    }

    func testCollectionKeepsImageAndRejectsOldPathAfterConfirmation() throws {
        let preview = ChatImagePreviewCollectionView(frame: CGRect(x: 0, y: 0, width: 240, height: 240))
        let local = item(path: "file:///tmp/local.jpg")
        let remote = item(path: "chat/remote.jpg")
        let photo = UIImage()
        preview.updateCollectionView([local], 240, [])
        preview.render(id: local.id, path: local.attachment.thumbResourcePath, state: .image(photo))
        let collection = try XCTUnwrap(preview.subviews.first as? UICollectionView)
        let layout = collection.collectionViewLayout
        preview.updateCollectionView([remote], 240, [])
        preview.render(id: local.id, path: local.attachment.thumbResourcePath, state: .image(UIImage()))
        XCTAssertTrue(collection.collectionViewLayout === layout)
        XCTAssertTrue(preview.currentImages().first.flatMap { $0 } === photo)
        preview.updateCollectionView([], 0, [])
        XCTAssertTrue(preview.currentImages().isEmpty)
    }

    func testThirtyImageBundleUsesIndividualFramesAndVisibleSubset() {
        let preview = ChatImagePreviewCollectionView(frame: CGRect(x: 0, y: 0, width: 240, height: 800))
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        host.addSubview(preview)
        let items = (0..<30).map { item(path: "chat/\($0).jpg", index: $0) }
        preview.updateCollectionView(items, 800, ChatMediaPreviewLayout.rows(count: 30))
        preview.layoutIfNeeded()
        let candidates = preview.viewportItems(in: host)
        XCTAssertEqual(candidates.count, 30)
        let expected = ChatMediaPreviewLayout.frames(count: 30, width: 240)
        for (candidate, frame) in zip(candidates, expected) {
            XCTAssertEqual(candidate.frame.minY, frame.minY, accuracy: 0.5)
            XCTAssertEqual(candidate.frame.height, frame.height, accuracy: 0.5)
        }
        let demands = ChatMediaViewportPolicy().demands(items: candidates, viewport: host.bounds, movingDown: true)
        XCTAssertEqual(demands.values.filter { $0 == .visible }.count, 9)
        XCTAssertLessThan(demands.count, 30)
    }

    func testPreviewPathsNeverIncludeRemoteOriginal() {
        let attachment = Attachment(type: .image, index: 0, pathThumb: "", pathOriginal: "chat/original.jpg",
                                    width: 100, height: 100, bytesOriginal: 100, hash: "hash")
        let preview = ChatImagePreviewItem(id: "item", displayIndex: 0, attachment: attachment, durationText: nil)
        XCTAssertTrue(preview.previewPaths.isEmpty)
    }

    private func imageView(in cell: ChatImagePreviewCell) throws -> UIImageView {
        try XCTUnwrap(cell.contentView.subviews.first as? UIImageView)
    }

    private func item(path: String, index: Int = 0, messageID: String = "message", hash: String = "local-hash") -> ChatImagePreviewItem {
        let attachment = Attachment(type: .image, index: index, pathThumb: path, pathOriginal: path,
                                    width: 100, height: 100, bytesOriginal: 100, hash: hash)
        return ChatImagePreviewItem(id: ChatImagePreviewItem.stableID(messageID: messageID, attachment: attachment),
                                    displayIndex: index, attachment: attachment, durationText: nil)
    }
}
