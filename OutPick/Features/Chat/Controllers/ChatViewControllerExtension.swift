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
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        
        // 터치된 뷰가 UIButton일 경우 제스처 제외
        if let touchedView = touch.view, touchedView is UIButton {
            return false
        }
        
        if let excludeView = touch.view, excludeView.tag == 99 || excludeView.tag == 98 {
            return false
        }
        
        return true
        
    }
}

extension ChatViewController: PHPickerViewControllerDelegate {
    private enum PickerConst { static let maxImagesPerMessage = 30 }

    /// PreparedImage -> 업로드 API 호환용 ImagePair로 변환
    private func toImagePairs(_ prepared: [PreparedImage]) -> [DefaultMediaProcessingService.ImagePair] {
        prepared.map {
            DefaultMediaProcessingService.ImagePair(
                index: $0.index,
                originalFileURL: $0.originalFileURL,
                thumbData: $0.thumbData,
                originalWidth: $0.originalWidth,
                originalHeight: $0.originalHeight,
                bytesOriginal: $0.bytesOriginal,
                sha256: $0.sha256
            )
        }
    }
    
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
                        guard let roomID = self.room?.ID,
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
            
            // 30장씩 배치 전송
            let total = imageResults.count
            let chunkSize = PickerConst.maxImagesPerMessage
            let chunks: [[PHPickerResult]] = stride(from: 0, to: total, by: chunkSize).map { start in
                let end = min(start + chunkSize, total)
                return Array(imageResults[start..<end])
            }
            
            if chunks.count > 1 {
                Task { @MainActor in
                    let lastCount = total % chunkSize == 0 ? chunkSize : total % chunkSize
                    AlertManager.showAlertNoHandler(
                        title: "이미지 다중 전송",
                        message: "총 \(total)장을 \(chunkSize)장 + \(lastCount)장으로 나눠 \(chunks.count)개의 메시지로 전송합니다.",
                        viewController: self
                    )
                }
            }
            
            convertImagesTask = Task {
                do {
                    for chunk in chunks {
                        try Task.checkCancellation()
                        
                        // 1) PHPickerResult 배열 -> [PreparedImage] -> [ImagePair] (썸네일 Data + 원본 파일URL + 메타)
                        let prepared = try await self.mediaProcessor.prepareImages(chunk)
                        let pairs = self.toImagePairs(prepared)
                        
                        // 2) 메시지/폴더 경로 식별자 준비
                        guard let room = self.room else {
                            self.cleanupPendingImageOriginalFiles(pairs)
                            continue
                        }
                        let roomID = room.ID ?? ""
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

                        await MainActor.run {
                            self.schedulePendingImageUpload(room: room, roomID: roomID, messageID: messageID, pairs: pairs)
                        }
                    }
                } catch MediaError.failedToConvertImage {
                    AlertManager.showAlertNoHandler(title: "이미지 변환 실패", message: "이미지를 다시 선택해 주세요/", viewController: self)
                } catch FirebaseStorageError.FailedToUploadImage {
                    print("이미지 업로드 실패")
                } catch FirebaseStorageError.FailedToFetchImage {
                    print("이미지 불러오기 실패")
                } catch {
                    print("알 수 없는 오류: \(error)")
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
        room: ChatRoom,
        roomID: String,
        messageID: String,
        pairs: [DefaultMediaProcessingService.ImagePair]
    ) async {
        do {
            guard mediaUploadUseCase.isSocketConnected else {
                await mediaUploadUseCase.cacheFailedImageThumbnails(pairs)
                if let message = await MainActor.run(body: {
                    self.stagedMessageForOutbox(messageID: messageID)
                }) {
                    await markOutgoingMessageFailed(message, error: ChatMediaUploadUseCaseError.socketDisconnectedBeforeUpload)
                }
                await MainActor.run {
                    self.markPendingImageUploadFailed(messageID: messageID)
                }
                return
            }

            let attachments = try await mediaUploadUseCase.uploadPendingImages(
                pairs: pairs,
                roomID: roomID,
                messageID: messageID,
                onProgress: { [weak self] fraction in
                    guard let self else { return }
                    Task { @MainActor in
                        self.setPendingImageUploadState(.uploading(fraction), for: messageID)
                    }
                }
            )

            await MainActor.run {
                self.setUploadedImageAttachments(attachments, for: messageID)
            }
            await markOutgoingImageUploadCompleted(messageID: messageID, attachments: attachments)
            try await mediaUploadUseCase.sendUploadedImages(room: room, attachments: attachments, clientMessageID: messageID)

            await MainActor.run {
                self.finishPendingImageUpload(messageID: messageID)
            }
        } catch {
            await mediaUploadUseCase.cacheFailedImageThumbnails(pairs)
            if let message = await MainActor.run(body: {
                self.stagedMessageForOutbox(messageID: messageID)
            }) {
                await markOutgoingMessageFailed(message, error: error)
            }
            await MainActor.run {
                self.markPendingImageUploadFailed(messageID: messageID)
            }
            print("업로드 실패:", error)
        }
    }
    
    func uploadPendingVideoMessage(
        roomID: String,
        messageID: String,
        prepared: PreparedVideo
    ) async {
        do {
            guard mediaUploadUseCase.isSocketConnected else {
                if let message = await MainActor.run(body: {
                    self.stagedMessageForOutbox(messageID: messageID)
                }) {
                    await markOutgoingMessageFailed(message, error: ChatMediaUploadUseCaseError.socketDisconnectedBeforeUpload)
                }
                await MainActor.run {
                    self.markPendingVideoUploadFailed(messageID: messageID)
                }
                return
            }

            let payload = try await mediaUploadUseCase.uploadVideo(
                roomID: roomID,
                messageID: messageID,
                prepared: prepared,
                onProgress: { [weak self] fraction in
                    guard let self else { return }
                    Task { @MainActor in
                        self.setPendingVideoUploadState(.uploading(fraction), for: messageID)
                    }
                }
            )

            await MainActor.run {
                self.setUploadedVideoPayload(payload, for: messageID)
            }
            await markOutgoingVideoUploadCompleted(messageID: messageID, payload: payload)
            try await mediaUploadUseCase.sendUploadedVideo(roomID: roomID, payload: payload)

            await MainActor.run {
                self.finishPendingVideoUpload(messageID: messageID)
            }
        } catch {
            // 업로드 실패 안내(미리보기 표시 후 노출)
            await MainActor.run {
                AlertManager.showAlertNoHandler(
                    title: "업로드 실패",
                    message: error.localizedDescription,
                    viewController: self
                )
            }
            
            if let message = await MainActor.run(body: {
                self.stagedMessageForOutbox(messageID: messageID)
            }) {
                await markOutgoingMessageFailed(message, error: error)
            }
            await MainActor.run {
                self.markPendingVideoUploadFailed(messageID: messageID)
            }
        }
    }

    func finalizeUploadedImageMessage(
        room: ChatRoom,
        messageID: String,
        attachments: [Attachment]
    ) async {
        do {
            try await mediaUploadUseCase.sendUploadedImages(
                room: room,
                attachments: attachments,
                clientMessageID: messageID
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
            try await mediaUploadUseCase.sendUploadedVideo(roomID: roomID, payload: payload)
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
