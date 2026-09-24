import XCTest
import UIKit
@testable import OutPick

@MainActor
final class ChatMediaViewportSurfaceTests: XCTestCase {
    func testCellStartsWithMemoryImageAndRejectsPreviousPathAfterReplacement() throws {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 500))
        let image = UIImage()
        func message(path: String) -> ChatMessage {
            ChatMessage(ID: "cache", seq: 1, roomID: "test", senderUID: "test", senderNickname: "테스트", msg: nil, sentAt: nil,
                attachments: [Attachment(type: .image, index: 0, pathThumb: path, pathOriginal: "original", width: 100, height: 100, bytesOriginal: 100, hash: path)])
        }
        let first = message(path: "old")
        cell.configureWithImage(with: first, cachedImage: { $0 == "old" ? image : nil }, avatarLoader: { _ in nil })
        cell.layoutIfNeeded()
        let preview = try XCTUnwrap(cell.contentView.subviews.compactMap { $0 as? ChatImagePreviewCollectionView }.first)
        preview.layoutIfNeeded()
        XCTAssertTrue(preview.currentImages().first! === image)
        let next = message(path: "new")
        cell.configureWithImage(with: next, cachedImage: { _ in nil }, avatarLoader: { _ in nil })
        let id = ChatImagePreviewItem.stableID(messageID: next.ID, attachment: next.attachments[0])
        preview.render(id: id, path: "old", state: .image(image))
        XCTAssertNil(preview.currentImages().first!)
    }

    func testLoadingEventUsesImageThatBecameReadyAfterCellConfiguration() {
        let preview = ChatImagePreviewCollectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        let attachment = Attachment(type: .image, index: 0, pathThumb: "thumb", pathOriginal: "original", width: 100, height: 100, bytesOriginal: 100, hash: "h")
        let item = ChatImagePreviewItem(id: "id", displayIndex: 0, attachment: attachment, durationText: nil)
        var ready: UIImage?
        preview.updateCollectionView([item], 100, [1], cachedImage: { _ in ready })
        preview.layoutIfNeeded()
        let image = UIImage()
        ready = image
        preview.render(id: "id", path: "thumb", state: .loading)
        XCTAssertTrue(preview.currentImages().first! === image)
    }

    func testMediaCellResizesWithoutReconfigureAndKeepsRenderedImage() throws {
        for count in [1, 30] {
            let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 1000))
            let attachments = (0..<count).map {
                Attachment(type: .image, index: $0, pathThumb: "thumb-\($0)", pathOriginal: "original-\($0)", width: 100, height: 100, bytesOriginal: 100, hash: "hash-\($0)")
            }
            let message = ChatMessage(ID: "rotation", seq: 1, roomID: "test", senderUID: "rotation-test", senderNickname: "테스트", msg: nil, sentAt: nil, attachments: attachments)
            cell.configureWithImage(with: message, avatarLoader: { _ in nil })
            let preview = try XCTUnwrap(cell.contentView.subviews.compactMap { $0 as? ChatImagePreviewCollectionView }.first)
            let image = UIImage()
            preview.render(id: ChatImagePreviewItem.stableID(messageID: message.ID, attachment: attachments[0]), path: "thumb-0", state: .image(image))
            for width: CGFloat in [390, 844, 390] {
                let target = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
                let size = cell.contentView.systemLayoutSizeFitting(target, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
                cell.frame.size = CGSize(width: width, height: size.height)
                cell.contentView.frame = cell.bounds
                cell.setNeedsLayout()
                cell.layoutIfNeeded()
                XCTAssertEqual(preview.bounds.width, width * 0.7, accuracy: 0.5)
                XCTAssertEqual(preview.bounds.height, ChatMediaPreviewLayout.height(count: count, width: width * 0.7), accuracy: 0.5)
                XCTAssertTrue(preview.currentImages()[0] === image)
            }
        }
    }

    func testMixedPhotoGIFAndVideoUseOnlyThumbnailDemand() async {
        let preview = ChatImagePreviewCollectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        let attachments = [
            Attachment(type: .image, index: 0, pathThumb: "photo-thumb", pathOriginal: "photo-original", width: 100, height: 100, bytesOriginal: 100, hash: "photo"),
            Attachment(type: .image, index: 1, pathThumb: "gif-thumb", pathOriginal: "animated.gif", width: 100, height: 100, bytesOriginal: 100, hash: "gif", mediaFormat: "gif", isAnimated: true),
            Attachment(type: .video, index: 2, pathThumb: "video-thumb", pathOriginal: "video.mp4", width: 100, height: 100, bytesOriginal: 100, hash: "video", duration: 12)
        ]
        let items = attachments.map {
            ChatImagePreviewItem(id: ChatImagePreviewItem.stableID(messageID: "mixed", attachment: $0),
                                 displayIndex: $0.index, attachment: $0, durationText: $0.type == .video ? "0:12" : nil)
        }
        preview.updateCollectionView(items, 100, [3])
        preview.layoutIfNeeded()
        XCTAssertTrue(items[1].isAnimatedGIF)
        XCTAssertTrue(items[2].isVideo)
        let candidates = preview.viewportItems(in: preview)
        let policy = ChatMediaViewportPolicy()
        var paths: [String] = []
        let loaded = expectation(description: "세 종류 썸네일 표시")
        loaded.expectedFulfillmentCount = 3
        let controller = ChatMediaViewportController { path, _ in
            paths.append(path)
            return UIImage()
        }
        controller.onChange = { id, path, state in
            preview.render(id: id, path: path, state: state)
            if case .image = state { loaded.fulfill() }
        }
        controller.resume()
        controller.update(items: candidates, demands: policy.demands(items: candidates, viewport: preview.bounds, movingDown: true), validIDs: Set(items.map(\.id)))
        await fulfillment(of: [loaded], timeout: 1)
        XCTAssertEqual(Set(paths), ["photo-thumb", "gif-thumb", "video-thumb"])
        XCTAssertEqual(preview.currentImages().compactMap { $0 }.count, 3)
        controller.endSession()
    }

    func testShareCardPreservesImageOnReconfigureAndRejectsOldPath() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 240, height: 76))
        let card = LookbookShareMessageContentView(frame: .zero)
        host.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            card.topAnchor.constraint(equalTo: host.topAnchor),
            card.widthAnchor.constraint(equalToConstant: 240),
            card.heightAnchor.constraint(equalToConstant: 76)
        ])
        func content(_ path: String) -> LookbookSharedContent {
            LookbookSharedContent(schemaVersion: 1, contentType: .brand, brandID: "brand", titleSnapshot: "공유 카드", thumbnailPathSnapshot: path)
        }
        let image = UIImage()
        card.configure(with: content("first"))
        card.render(path: "first", state: .image(image))
        card.configure(with: content("first"))
        let thumbnail = try XCTUnwrap(card.subviews.first as? UIImageView)
        XCTAssertTrue(thumbnail.image === image)
        card.configure(with: content("second"))
        card.render(path: "first", state: .image(image))
        XCTAssertFalse(thumbnail.image === image)
        host.layoutIfNeeded()
        XCTAssertEqual(card.thumbnailFrame(in: card).width, 56, accuracy: 0.01)
        XCTAssertEqual(card.thumbnailFrame(in: card).height, 56, accuracy: 0.01)
        card.prepareForReuse()
        card.render(path: "second", state: .image(image))
        XCTAssertFalse(thumbnail.image === image)
    }
}
