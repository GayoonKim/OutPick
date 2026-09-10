//
//  ChatExtension.swift
//  OutPick
//
//  Created by 김가윤 on 1/16/25.
//

import Foundation
import UIKit
import PhotosUI
import UniformTypeIdentifiers

// 내비게이션 아이템 타이틀 설정
extension UINavigationItem {
    func setTitle(title: String, subtitle: String) {
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 17)
        titleLabel.sizeToFit()
        
        let subTitleLabel = UILabel()
        subTitleLabel.text = subtitle
        subTitleLabel.font = UIFont.systemFont(ofSize: 12)
        subTitleLabel.textAlignment = .center
        subTitleLabel.sizeToFit()
        
        let stackView = UIStackView(arrangedSubviews: [titleLabel, subTitleLabel])
        stackView.distribution = .equalCentering
        stackView.axis = .vertical
        stackView.alignment = .center
        
        let width = max(titleLabel.frame.size.width, subTitleLabel.frame.size.width)
        stackView.frame = CGRect(x: 0, y: 0, width: width, height: 35)
        
        titleLabel.sizeToFit()
        subTitleLabel.sizeToFit()
        
        self.titleView = stackView
        
    }
}

extension UITextView {
    func alignTextVertically() {
        
        var topConstraint = (self.bounds.size.height - (self.contentSize.height)) / 2
        topConstraint = topConstraint < 0.0 ? 0.0 : topConstraint
        self.contentInset.left = 5
        self.contentInset.top = topConstraint
        
    }
}

extension ChatViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touchedView = touch.view
        var containsControl = false
        var isMessageCellTouch = false

        while let currentView = touchedView {
            if currentView is UITextField || currentView is UITextView {
                return false
            }
            containsControl = containsControl || currentView is UIControl
            isMessageCellTouch = isMessageCellTouch || currentView is ChatMessageCell
            touchedView = currentView.superview
        }

        return isMessageCellTouch || !containsControl
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // background dismiss와 cell 전용 tap action을 함께 실행한다.
        true
    }
}

extension ChatViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty, let room, !isParticipantPreviewMode else { return }
        startMediaSelection(results, room: room)
    }
}

extension ChatViewController: UIImagePickerControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
//        if let editedImage = info[.editedImage] as? UIImage {
//
//        } else if let originalImage = info[.originalImage] as? UIImage {
//
//        }
        dismiss(animated: true)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: -  video 관련
extension ChatViewController {
    func performQueuedMediaContinuation(messageID: String, isVideo: Bool,
        operation: () async -> Void) async {
        do {
            try await mediaUploadUseCase.beginProcessingBatch(uploadID: messageID)
            try Task.checkCancellation()
            if isVideo { setPendingVideoUploadState(.processing, for: messageID) }
            else { setPendingImageUploadState(.processing, for: messageID) }
            await operation()
            await finishStagedMediaPresentation()
        } catch {
            if isVideo { markPendingVideoUploadFailed(messageID: messageID) }
            else { markPendingImageUploadFailed(messageID: messageID) }
        }
        if !mediaConfirmationsInFlight.contains(messageID) {
            await mediaUploadUseCase.finishImageUploadTurn(uploadID: messageID)
        }
    }

    func uploadPendingImageMessage(
        roomID: String,
        messageID: String,
        pairs: [ProcessedImage],
        clientMutationID: String = UUID().uuidString
    ) async {
        let result = await enqueuePendingImageMessage(
            roomID: roomID,
            messageID: messageID,
            pairs: pairs,
            clientMutationID: clientMutationID
        )
        guard let snapshot = result else {
            if !mediaConfirmationsInFlight.contains(messageID) {
                await mediaUploadUseCase.finishImageUploadTurn(uploadID: messageID)
            }
            return
        }
        await monitorMediaProcessing(
            roomID: roomID,
            messageID: messageID,
            clientMutationID: clientMutationID,
            isVideo: false,
            initial: snapshot
        )
        if !mediaConfirmationsInFlight.contains(messageID),
           (stagedMessageForOutbox(messageID: messageID)?.seq ?? 0) <= 0 {
            await mediaUploadUseCase.finishImageUploadTurn(uploadID: messageID)
        }
    }

    func enqueuePendingImageMessage(
        roomID: String,
        messageID: String,
        pairs: [ProcessedImage],
        clientMutationID: String
    ) async -> ChatMediaProcessingSnapshot? {
        do {
            let snapshot = try await mediaUploadUseCase.enqueueImageProcessing(
                pairs: pairs,
                roomID: roomID,
                uploadID: messageID,
                clientMutationID: clientMutationID,
                onWaitingForSlot: { [weak self] in
                    await self?.outgoingOutboxUseCase.markMediaAttempt(messageID: messageID,
                        clientMutationID: clientMutationID, kind: "images")
                    await MainActor.run {
                        self?.setPendingImageUploadState(.waitingForSlot, for: messageID)
                    }
                },
                onReservation: { [weak self] reservation in
                    await self?.markOutgoingMediaReservation(
                        messageID: messageID,
                        reservation: reservation
                    )
                },
                onProgress: { [weak self] fraction in
                    guard let self else { return }
                    Task { @MainActor in
                        self.setPendingImageUploadState(.uploading(fraction), for: messageID)
                    }
                }
            )
            await markOutgoingMediaProcessing(messageID: messageID, snapshot: snapshot)
            return snapshot
        } catch {
            let wasRemovedInMemory = await MainActor.run {
                self.isMembershipRemovedByModeration
            }
            let serverAccess = await loadRoomAccessAfterOutgoingFailure()
            let wasRemovedByModeration = wasRemovedInMemory || serverAccess == .banned
            await mediaUploadUseCase.cacheFailedImageThumbnails(pairs)
            if !wasRemovedByModeration, let message = await MainActor.run(body: {
                self.stagedMessageForOutbox(messageID: messageID)
            }) {
                await markOutgoingMessageFailed(message, error: error)
            }
            await MainActor.run {
                if !wasRemovedByModeration {
                    self.markPendingImageUploadFailed(messageID: messageID)
                }
            }
            await MainActor.run { self.failMediaNetworkSession(error) }
            print("업로드 실패:", error)
            return nil
        }
    }
    
    func uploadPendingVideoMessage(
        roomID: String,
        messageID: String,
        prepared: PreparedVideo,
        clientMutationID: String = UUID().uuidString
    ) async {
        do {
            let snapshot = try await mediaUploadUseCase.enqueueVideoProcessing(
                prepared: prepared,
                roomID: roomID,
                uploadID: messageID,
                clientMutationID: clientMutationID,
                onWaitingForSlot: { [weak self] in
                    await self?.outgoingOutboxUseCase.markMediaAttempt(messageID: messageID,
                        clientMutationID: clientMutationID, kind: "video")
                    await MainActor.run {
                        self?.setPendingVideoUploadState(.waitingForSlot, for: messageID)
                    }
                },
                onReservation: { [weak self] reservation in
                    await self?.markOutgoingMediaReservation(
                        messageID: messageID,
                        reservation: reservation
                    )
                },
                onProgress: { [weak self] fraction in
                    guard let self else { return }
                    Task { @MainActor in
                        self.setPendingVideoUploadState(.uploading(fraction), for: messageID)
                    }
                }
            )
            await markOutgoingMediaProcessing(messageID: messageID, snapshot: snapshot)
            await monitorMediaProcessing(
                roomID: roomID,
                messageID: messageID,
                clientMutationID: clientMutationID,
                isVideo: true,
                initial: snapshot
            )
            if !mediaConfirmationsInFlight.contains(messageID),
               (stagedMessageForOutbox(messageID: messageID)?.seq ?? 0) <= 0 {
                await mediaUploadUseCase.finishVideoUploadTurn(uploadID: messageID)
            }
        } catch {
            let wasRemovedInMemory = await MainActor.run {
                self.isMembershipRemovedByModeration
            }
            let serverAccess = await loadRoomAccessAfterOutgoingFailure()
            let wasRemovedByModeration = wasRemovedInMemory || serverAccess == .banned
            if wasRemovedByModeration {
                await MainActor.run {
                    AlertManager.showAlertNoHandler(
                        title: "전송을 중단했어요",
                        message: "채팅방 참여가 제한되어 전송을 중단했어요.",
                        viewController: self
                    )
                }
            }
            
            if !wasRemovedByModeration, let message = await MainActor.run(body: {
                self.stagedMessageForOutbox(messageID: messageID)
            }) {
                await markOutgoingMessageFailed(message, error: error)
            }
            await MainActor.run {
                if !wasRemovedByModeration {
                    self.markPendingVideoUploadFailed(messageID: messageID)
                }
            }
            await MainActor.run { self.failMediaNetworkSession(error) }
            print("동영상 업로드 실패:", error)
            if !mediaConfirmationsInFlight.contains(messageID) {
                await mediaUploadUseCase.finishVideoUploadTurn(uploadID: messageID)
            }
        }
    }

    func monitorMediaProcessing(
        roomID: String,
        messageID: String,
        clientMutationID: String,
        isVideo: Bool,
        initial: ChatMediaProcessingSnapshot
    ) async {
        var snapshot = initial
        let delays: [UInt64] = [2, 4, 8, 15, 30]
        var attempt = 0
        var consecutiveFailures = 0
        while !Task.isCancelled {
            let alreadyConfirmed = await MainActor.run {
                (self.stagedMessageForOutbox(messageID: messageID)?.seq ?? 0) > 0
            }
            if alreadyConfirmed { return }
            await markOutgoingMediaProcessing(messageID: messageID, snapshot: snapshot)
            if snapshot.processingStatus == .ready {
                await MainActor.run {
                    self.pendingMediaUploadStore.markServerReady(for: messageID)
                    if isVideo { self.setPendingVideoUploadState(.processing, for: messageID) }
                    else { self.setPendingImageUploadState(.processing, for: messageID) }
                }
                // Socket 누락 시에도 공개 원본 메시지를 읽어 같은 수신 경로로 확정한다.
                if let confirmed = try? await mediaUploadUseCase.confirmedMessage(roomID: roomID, messageID: messageID) {
                    await handleIncomingMessage(confirmed)
                }
            }
            let isTerminal = await MainActor.run { () -> Bool in
                let setState: (ChatPendingMediaUploadState) -> Void = { state in
                    if isVideo {
                        self.setPendingVideoUploadState(state, for: messageID)
                    } else {
                        self.setPendingImageUploadState(state, for: messageID)
                    }
                }
                switch snapshot.processingStatus {
                case .uploading:
                    setState(.uploading(1))
                    return false
                case .queued:
                    setState(.queued)
                    return false
                case .processing:
                    setState(.processing)
                    return false
                case .ready:
                    guard (self.stagedMessageForOutbox(messageID: messageID)?.seq ?? 0) > 0 else { return false }
                    if isVideo {
                        self.finishPendingVideoUpload(messageID: messageID)
                    } else {
                        self.finishPendingImageUpload(messageID: messageID)
                    }
                    return true
                case .failed, .canceled:
                    setState(.failed)
                    return true
                case .expired:
                    setState(.expired)
                    return true
                }
            }
            if isTerminal { return }

            let delay = consecutiveFailures > 0 ? UInt64(consecutiveFailures) : delays[min(attempt, delays.count - 1)]
            attempt += 1
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled else { break }
            do {
                snapshot = try await mediaUploadUseCase.mediaProcessingStatus(
                    roomID: roomID,
                    uploadID: messageID,
                    clientMutationID: clientMutationID
                )
                consecutiveFailures = 0
            } catch {
                consecutiveFailures += 1
                if consecutiveFailures >= 3 {
                    await MainActor.run { self.failMediaNetworkSession(error) }
                    break
                }
            }
        }
        if Task.isCancelled || consecutiveFailures >= 3 {
            await outgoingOutboxUseCase.markMediaRestoreRequiresManualRetry(messageID: messageID)
            if let terminal = try? await mediaUploadUseCase.cancelMediaProcessing(roomID: roomID,
                uploadID: messageID, clientMutationID: clientMutationID) {
                await outgoingOutboxUseCase.markMediaProcessing(messageID: messageID, snapshot: terminal)
                if terminal.processingStatus == .ready {
                    await MainActor.run {
                        self.pendingMediaUploadStore.markServerReady(for: messageID)
                        if isVideo { self.setPendingVideoUploadState(.processing, for: messageID) }
                        else { self.setPendingImageUploadState(.processing, for: messageID) }
                    }
                    if let confirmed = try? await mediaUploadUseCase.confirmedMessage(roomID: roomID, messageID: messageID) {
                        await handleIncomingMessage(confirmed)
                    }
                }
            }
        }
    }

    func finalizeUploadedImageMessage(
        room: ChatRoom,
        messageID: String,
        attachments: [Attachment]
    ) async {
        do {
            let receipt = try await mediaUploadUseCase.sendUploadedImages(
                room: room,
                attachments: attachments,
                clientMessageID: messageID,
                ensureReservation: true
            )
            await reconcileServerConfirmedOutgoingMessage(
                receipt: receipt,
                confirmedAttachments: attachments
            )
            await MainActor.run {
                self.finishPendingImageUpload(messageID: messageID)
            }
        } catch {
            await MainActor.run {
                self.markPendingImageUploadFailed(messageID: messageID)
            }
            if let message = await MainActor.run(body: {
                self.stagedMessageForOutbox(messageID: messageID)
            }) {
                await markOutgoingMessageFailed(message, error: error)
            }
        }
    }

    func finalizeUploadedVideoMessage(
        roomID: String,
        messageID: String,
        payload: VideoMetaPayload
    ) async {
        do {
            let receipt = try await mediaUploadUseCase.sendUploadedVideo(
                roomID: roomID,
                payload: payload,
                ensureReservation: true
            )
            await reconcileServerConfirmedOutgoingMessage(
                receipt: receipt,
                confirmedAttachments: [payload.confirmedAttachment]
            )
            await MainActor.run {
                self.finishPendingVideoUpload(messageID: messageID)
            }
        } catch {
            await MainActor.run {
                self.markPendingVideoUploadFailed(messageID: messageID)
            }
            if let message = await MainActor.run(body: {
                self.stagedMessageForOutbox(messageID: messageID)
            }) {
                await markOutgoingMessageFailed(message, error: error)
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}
