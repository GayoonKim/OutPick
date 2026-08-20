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
    private enum PickerConst { static let maxImagesPerMessage = 30 }
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        var resultsForVideos: [PHPickerResult] = []
        var resultsForImages: [PHPickerResult] = []
        
        for result in results {
            let itemProvider = result.itemProvider
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                resultsForVideos.append(result)
            } else if itemProvider.canLoadObject(ofClass: UIImage.self) {
                resultsForImages.append(result)
            }
        }
        
        // // 720p 표준: .standard720
        // 데이터 절약 모드: .dataSaver720
        // 1080p 고화질: .high1080
        if !resultsForVideos.isEmpty {
            convertVideosTask = Task {
                for result in resultsForVideos {
                    do {
                        // 1) 비디오 개별 변환 (한 메시지 = 한 동영상)
                        let prepared = try await self.mediaProcessor.prepareVideo(result, preset: .standard720)
                        
                        // 2) 방 식별 후 pending thumbnail을 먼저 표시하고 업로드+브로드캐스트
                        guard let roomID = self.room?.id,
                              !roomID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            await MainActor.run {
                                AlertManager.showAlertNoHandler(
                                    title: "방 정보를 찾을 수 없습니다",
                                    message: "동영상을 전송할 방이 없습니다.",
                                    viewController: self
                                )
                            }
                            continue
                        }

                        let messageID = UUID().uuidString
                        let staged = await MainActor.run {
                            self.stagePendingVideoMessage(
                                roomID: roomID,
                                messageID: messageID,
                                prepared: prepared
                            )
                        }
                        if !staged {
                            await MainActor.run {
                                AlertManager.showAlertNoHandler(
                                    title: "비디오 미리보기 실패",
                                    message: "동영상 미리보기를 만들지 못했습니다. 다시 선택해 주세요.",
                                    viewController: self
                                )
                            }
                            continue
                        }

                        if let pendingMessage = await MainActor.run(body: {
                            self.stagedMessageForOutbox(messageID: messageID)
                        }) {
                            await self.stageOutgoingVideoOutbox(message: pendingMessage, prepared: prepared)
                        }

                        await MainActor.run {
                            self.schedulePendingVideoUpload(
                                roomID: roomID,
                                messageID: messageID,
                                prepared: prepared
                            )
                        }
                        
                    } catch {
                        await MainActor.run {
                            AlertManager.showAlertNoHandler(
                                title: "비디오 변환 실패",
                                message: "압축 중 오류가 발생했습니다.\n\(error.localizedDescription)",
                                viewController: self
                            )
                        }
                        // 다음 비디오 계속 처리
                        continue
                    }
                }
            }
        }
        
        if !resultsForImages.isEmpty {
            let imageResults = resultsForImages
            
            convertImagesTask = Task {
                var normalized: [ProcessedImage] = []
                var rejectedCount = 0
                for (index, result) in imageResults.enumerated() {
                    do {
                        try Task.checkCancellation()
                        normalized.append(try await self.mediaProcessor.prepareChatImage(result, index: index))
                    } catch is CancellationError {
                        return
                    } catch {
                        rejectedCount += 1
                    }
                }
                let chunks = ChatMediaSelectionChunker.chunks(normalized)
                if rejectedCount > 0 {
                    await MainActor.run {
                        AlertManager.showAlertNoHandler(
                            title: "일부 이미지를 제외했어요",
                            message: "지원하지 않거나 제한을 초과한 \(rejectedCount)장은 제외했습니다. 전송 가능한 이미지 \(normalized.count)장을 전송합니다.",
                            viewController: self
                        )
                    }
                }
                var stagedChunks: [(roomID: String, messageID: String, pairs: [ProcessedImage])] = []
                for pairs in chunks {
                    do {
                        try Task.checkCancellation()
                        // 2) 메시지/폴더 경로 식별자 준비
                        guard let room = self.room else {
                            self.cleanupPendingImageOriginalFiles(pairs)
                            continue
                        }
                        let roomID = room.id
                        let messageID = UUID().uuidString
                        let staged = await MainActor.run {
                            self.stagePendingImageMessage(room: room, roomID: roomID, messageID: messageID, pairs: pairs)
                        }
                        if !staged {
                            self.cleanupPendingImageOriginalFiles(pairs)
                            continue
                        }

                        if let pendingMessage = await MainActor.run(body: {
                            self.stagedMessageForOutbox(messageID: messageID)
                        }) {
                            await self.stageOutgoingImageOutbox(message: pendingMessage, pairs: pairs)
                        }
                        stagedChunks.append((roomID, messageID, pairs))
                    } catch is CancellationError {
                        self.cleanupPendingImageOriginalFiles(pairs)
                        return
                    }
                }
                // 여러 메시지로 분할된 선택은 모든 로컬 버블을 먼저 만든 뒤
                // 앞 chunk가 terminal이 되어 principal slot을 반환할 때까지 순차 실행한다.
                for staged in stagedChunks {
                    guard !Task.isCancelled else { return }
                    let clientMutationID = UUID().uuidString
                    await self.uploadPendingImageMessage(
                        roomID: staged.roomID,
                        messageID: staged.messageID,
                        pairs: staged.pairs,
                        clientMutationID: clientMutationID
                    )
                }
            }
        }
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
    func uploadPendingImageMessage(
        roomID: String,
        messageID: String,
        pairs: [ProcessedImage],
        clientMutationID: String = UUID().uuidString
    ) async {
        guard let snapshot = await enqueuePendingImageMessage(
            roomID: roomID,
            messageID: messageID,
            pairs: pairs,
            clientMutationID: clientMutationID
        ) else {
            return
        }
        await monitorMediaProcessing(
            roomID: roomID,
            messageID: messageID,
            clientMutationID: clientMutationID,
            isVideo: false,
            initial: snapshot
        )
        await mediaUploadUseCase.finishImageUploadTurn(uploadID: messageID)
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
            await mediaUploadUseCase.finishVideoUploadTurn(uploadID: messageID)
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
            print("동영상 업로드 실패:", error)
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
        while !Task.isCancelled {
            await markOutgoingMediaProcessing(messageID: messageID, snapshot: snapshot)
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

            let delay = delays[min(attempt, delays.count - 1)]
            attempt += 1
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled else { return }
            do {
                snapshot = try await mediaUploadUseCase.mediaProcessingStatus(
                    roomID: roomID,
                    uploadID: messageID,
                    clientMutationID: clientMutationID
                )
            } catch {
                // 일시적인 연결 실패는 다음 backoff 주기에 다시 조회한다.
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
