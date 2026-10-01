import UIKit

extension ChatViewController {
    func prepareInitialDiskImages(readBoundarySeq: Int64?, messages suppliedMessages: [ChatMessage]? = nil) {
        guard mediaDiskPreparationActive, UIApplication.shared.applicationState != .background else { return }
        let messages = suppliedMessages ?? messageWindowStore.visibleMessages
        let anchor = readBoundarySeq.flatMap { boundary in messages.firstIndex { $0.seq > boundary } } ?? max(0, messages.count - 1)
        let groups = messages.map { message -> [String] in
            guard !message.isDeleted else { return [] }
            if message.isLookbookShareMessage {
                guard let path = message.sharedContent?.thumbnailPathSnapshot else { return [] }
                return [path]
            }
            return message.displayableAttachments.map(\.thumbResourcePath)
        }
        let paths = ChatMediaViewportPolicy().initialDiskPreparationPaths(groups: groups, anchor: anchor)
        let resourcesByPath = Dictionary(messages.flatMap { message in
            message.displayableAttachments.map { attachment in
                (attachment.thumbResourcePath, ChatMediaCacheResource.attachment(
                    path: attachment.thumbResourcePath,
                    generation: attachment.generationThumb,
                    mediaExpiresAt: message.mediaExpiresAt
                ))
            }
        }, uniquingKeysWith: { first, _ in first })
        ImageCacheMetrics.shared.mark("chatDiskPreparation.initial", outcome: "candidates_\(paths.count)")
        mediaViewport.prepareDiskBeforeLayout(paths: paths, resourcesByPath: resourcesByPath)
    }

    func resetMediaScrollPrediction() {
        mediaViewportVelocityY = 0
        mediaViewportSampleTime = nil
        mediaViewportTargetY = nil
    }

    func recordMediaScrollPrediction(_ scrollView: UIScrollView) {
        guard scrollView.isDragging || scrollView.isDecelerating else {
            resetMediaScrollPrediction()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        defer { mediaViewportSampleTime = now }
        guard let time = mediaViewportSampleTime, let previous = mediaViewportLastY,
              now > time, now - time < 0.25 else { return }
        let current = scrollView.bounds.minY + scrollView.adjustedContentInset.top
        let velocity = (current - previous) / CGFloat(now - time)
        if velocity * mediaViewportVelocityY < 0 { mediaViewportTargetY = nil }
        mediaViewportVelocityY = velocity
    }

    func bindMediaViewport() {
        mediaViewport.onChange = { [weak self] id, path, state in
            guard let self else { return }
            for case let cell as ChatMessageCell in self.chatMessageCollectionView.visibleCells {
                cell.renderMedia(id: id, path: path, state: state)
            }
        }
    }

    func scheduleMediaViewportUpdate() {
        guard mediaViewportActive, !mediaViewportUpdateScheduled else { return }
        mediaViewportUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.mediaViewportUpdateScheduled = false
            self.updateMediaViewport()
        }
    }

    func updateMediaViewport() {
        guard mediaViewportActive, UIApplication.shared.applicationState != .background,
              isViewLoaded, view.window != nil, let dataSource else { return }
        let collection = chatMessageCollectionView
        let viewport = collection.bounds.inset(by: collection.adjustedContentInset)
        guard viewport.height > 0 else { return }
        if let previous = mediaViewportLastY, previous != viewport.minY {
            mediaViewportMovingDown = viewport.minY > previous
        }
        mediaViewportLastY = viewport.minY
        let policy = ChatMediaViewportPolicy()
        var candidates: [ChatMediaViewportItem] = []
        var validIDs = Set<String>()
        let items = dataSource.snapshot().itemIdentifiers
        for (index, item) in items.enumerated() {
            guard case .message(let snapshotMessage) = item else { continue }
            let message = messageWindowStore.message(for: snapshotMessage.ID) ?? snapshotMessage
            guard !message.isDeleted else { continue }
            let attachments = message.displayableAttachments
            if message.isLookbookShareMessage {
                validIDs.insert(message.ID + "#share")
            } else {
                validIDs.formUnion(attachments.map { ChatImagePreviewItem.stableID(messageID: message.ID, attachment: $0) })
            }
            let indexPath = IndexPath(item: index, section: 0)
            guard let attributes = collection.collectionViewLayout.layoutAttributesForItem(at: indexPath) else { continue }
            if let cell = collection.cellForItem(at: indexPath) as? ChatMessageCell,
               cell.representedMessageID == message.ID {
                candidates.append(contentsOf: cell.mediaViewportItems(in: collection))
                continue
            }
            // 셀을 생성하지 않고 동일 행 배치와 본문의 bottom anchor로 주변 좌표를 계산한다.
            let frame = attributes.frame
            let isMine = LoginManager.shared.canonicalUserID == message.senderUID
            if message.isLookbookShareMessage {
                guard let path = message.sharedContent?.thumbnailPathSnapshot else { continue }
                let x = isMine ? frame.maxX - 8 - frame.width * 0.72 + 10 : frame.minX + 63
                candidates.append(ChatMediaViewportItem(id: message.ID + "#share", path: path,
                    frame: CGRect(x: x, y: frame.maxY - 8 - 76 + 10, width: 56, height: 56),
                    cacheResource: .sharedContent(path: path)))
            } else {
                let width = frame.width * 0.7
                let height = ChatMediaPreviewLayout.height(count: attachments.count, width: width)
                let x = isMine ? frame.maxX - 8 - width : frame.minX + 53
                let y = frame.maxY - 8 - height
                let frames = ChatMediaPreviewLayout.frames(count: attachments.count, width: width)
                for (attachment, localFrame) in zip(attachments, frames) {
                    candidates.append(ChatMediaViewportItem(
                        id: ChatImagePreviewItem.stableID(messageID: message.ID, attachment: attachment),
                        path: attachment.thumbResourcePath,
                        frame: localFrame.offsetBy(dx: x, dy: y),
                        cacheResource: ChatMediaCacheResource.attachment(
                            path: attachment.thumbResourcePath,
                            generation: attachment.generationThumb,
                            mediaExpiresAt: message.mediaExpiresAt
                        )))
                }
            }
        }
        mediaViewport.update(items: candidates,
            demands: policy.demands(items: candidates, viewport: viewport, movingDown: mediaViewportMovingDown,
                                    velocityY: mediaViewportVelocityY, targetY: mediaViewportTargetY),
            validIDs: validIDs, cancelOutsideImmediately: abs(mediaViewportVelocityY) > viewport.height * 2,
            diskPreparationPaths: mediaInitialSnapshotPending || mediaLocalPreparationWindow != nil || !mediaDiskPreparationActive ? nil : policy.diskPreparationPaths(items: candidates, viewport: viewport))
    }
}
