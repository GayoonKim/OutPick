//
//  ImageViewerPagePolicyTests.swift
//  OutPickTests
//
//  Created by Codex on 6/26/26.
//

import Testing
import UIKit
@testable import OutPick

struct ImageViewerPagePolicyTests {
    @Test func previewItemPathsPreferThumbnailThenOriginalAndRemoveDuplicates() {
        let item = ChatImagePreviewItem(
            id: "message-1#0#image",
            displayIndex: 0,
            attachment: makeAttachment(
                pathThumb: "rooms/room-1/messages/message-1/images/image-sha/thumb.jpg",
                pathOriginal: "rooms/room-1/messages/message-1/images/image-sha/original.jpg"
            ),
            durationText: nil
        )

        #expect(item.previewPaths == [
            "rooms/room-1/messages/message-1/images/image-sha/thumb.jpg",
            "rooms/room-1/messages/message-1/images/image-sha/original.jpg"
        ])

        let duplicateItem = ChatImagePreviewItem(
            id: "message-1#1#image",
            displayIndex: 1,
            attachment: makeAttachment(
                index: 1,
                pathThumb: "file:///tmp/pending-preview.jpg",
                pathOriginal: "file:///tmp/pending-preview.jpg",
                hash: "pending-sha"
            ),
            durationText: nil
        )

        #expect(duplicateItem.previewPaths == ["file:///tmp/pending-preview.jpg"])
    }

    @Test func displayableAttachmentsSortByAttachmentIndexAndExcludeEmptyPayloads() {
        let message = ChatMessage(
            ID: "message-1",
            seq: 1,
            roomID: "room-1",
            senderUID: "sender@example.com",
            senderEmail: nil,
            senderNickname: "sender",
            senderAvatarPath: nil,
            msg: nil,
            sentAt: Date(timeIntervalSince1970: 0),
            attachments: [
                makeAttachment(index: 20, pathThumb: "thumb-20.jpg", pathOriginal: "original-20.jpg", hash: "sha-20"),
                makeAttachment(index: 10, pathThumb: "", pathOriginal: "", hash: "empty-sha"),
                makeAttachment(index: 0, pathThumb: "", pathOriginal: "original-0.jpg", hash: "sha-0")
            ],
            replyPreview: nil
        )

        #expect(message.displayableAttachments.map { $0.index } == [0, 20])
        #expect(message.displayableImageAttachments.map { $0.hash } == ["sha-0", "sha-20"])
        #expect(message.hasDisplayableAttachments)
        #expect(message.hasDisplayableImages)
    }

    @Test func commonViewerPageSupportsLocalOnlyInitialImageContract() throws {
        let image = try #require(makeImage())

        let page = ImageViewerPage(
            initialImage: image,
            thumbnailPath: nil,
            originalPath: nil
        )

        #expect(page.initialImage === image)
        #expect(page.thumbnailImage == nil)
        #expect(page.thumbnailPath == nil)
        #expect(page.originalPath == nil)
        #expect(page.shouldAlwaysResolveThumbnail == false)
    }

    @Test func progressivePageAliasKeepsCommonViewerContractDefaults() {
        let page = SimpleImageViewerVC.ProgressivePage(
            thumbnailPath: "thumb.jpg",
            originalPath: "original.jpg",
            shouldAlwaysResolveThumbnail: true
        )

        #expect(page.thumbnailPath == "thumb.jpg")
        #expect(page.originalPath == "original.jpg")
        #expect(page.shouldAlwaysResolveThumbnail)
    }

    private func makeAttachment(
        type: OutPick.Attachment.AttachmentType = .image,
        index: Int = 0,
        pathThumb: String,
        pathOriginal: String,
        hash: String = "image-sha"
    ) -> OutPick.Attachment {
        OutPick.Attachment(
            type: type,
            index: index,
            pathThumb: pathThumb,
            pathOriginal: pathOriginal,
            width: 100,
            height: 100,
            bytesOriginal: 100,
            hash: hash
        )
    }

    private func makeImage() -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }
}
