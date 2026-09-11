import UIKit
import PhotosUI

extension ChatViewController {
    func startMediaSelection(_ results: [PHPickerResult], room: ChatRoom) {
        let id = UUID().uuidString
        #if DEBUG
        print("[MediaQA] event=selection_started selectionID=\(id) count=\(results.count) uptime=\(ProcessInfo.processInfo.systemUptime) epoch=\(Date().timeIntervalSince1970)")
        #endif
        let sender = chatRoomViewModel.currentUserUID
        mediaSessionStopped = false
        mediaNetworkFailed = false
        mediaSelectionTasks[id] = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.mediaSelectionUseCase.beginSelection(id)
                #if DEBUG
                print("[MediaQA] event=selection_turn_acquired selectionID=\(id) uptime=\(ProcessInfo.processInfo.systemUptime)")
                #endif
                do {
                    let selection = try await self.mediaSelectionUseCase.acquire(results, roomID: room.id, senderUID: sender, id: id)
                    #if DEBUG
                    print("[MediaQA] event=originals_acquired selectionID=\(id) uptime=\(ProcessInfo.processInfo.systemUptime)")
                    #endif
                    if !Task.isCancelled, !self.mediaSessionStopped, self.chatRoomViewModel.currentUserUID == sender {
                        await self.processMediaSelection(selection, room: room)
                    }
                } catch {
                    #if DEBUG
                    let failure = error as NSError
                    print("[MediaQA] event=original_acquisition_failed selectionID=\(id) domain=\(failure.domain) code=\(failure.code) canceled=\(Task.isCancelled)")
                    #endif
                }
                await self.mediaSelectionUseCase.endSelection(id)
            } catch {
                #if DEBUG
                let failure = error as NSError
                print("[MediaQA] event=selection_turn_failed selectionID=\(id) domain=\(failure.domain) code=\(failure.code) canceled=\(Task.isCancelled)")
                #endif
                // 전체 원본 확보 전 실패/취소에는 버블이나 안내를 만들지 않는다.
            }
            self.mediaSelectionTasks.removeValue(forKey: id)
            if !self.mediaSessionStopped { await self.restoreMediaSelections(room: room) }
        }
    }

    func processMediaSelection(_ selection: ChatMediaSelection, room: ChatRoom) async {
        var committedIDs: [String] = []
        do {
            let rejected = try await mediaSelectionUseCase.process(selection, onChunk: { [weak self] id, chunk in
                guard let self, !self.mediaSessionStopped, !Task.isCancelled else { throw CancellationError() }
                switch chunk {
                case .images(let pairs):
                    #if DEBUG
                    print("[MediaQA] event=chunk_prepared selectionID=\(selection.selectionID) messageID=\(id) count=\(pairs.count) uptime=\(ProcessInfo.processInfo.systemUptime)")
                    #endif
                    guard !self.mediaSessionStopped, !Task.isCancelled else {
                        throw CancellationError()
                    }
                    guard self.stagePendingImageMessage(room: room, roomID: room.id, messageID: id, pairs: pairs),
                          let message = self.stagedMessageForOutbox(messageID: id) else {
                        throw MediaError.failedToConvertImage
                    }
                    await self.stageOutgoingImageOutbox(message: message, pairs: pairs)
                    if case .uploadImages(_, _, let owned)? = await self.outgoingOutboxUseCase.retryPayload(messageID: id, room: room) {
                        _ = self.stagePendingImageMessage(room: room, roomID: room.id, messageID: id, pairs: owned)
                    }
                case .video(let video):
                    guard self.stagePendingVideoMessage(roomID: room.id, messageID: id, prepared: video),
                          let message = self.stagedMessageForOutbox(messageID: id) else {
                        throw MediaError.failedToConvertImage
                    }
                    await self.stageOutgoingVideoOutbox(message: message, prepared: video)
                case .failedVideo(let source):
                    try await self.mediaSelectionUseCase.preserveFailedVideo(source, id: id, roomID: room.id,
                        senderUID: self.chatRoomViewModel.currentUserUID)
                case .failedImages(let sources):
                    try await self.mediaSelectionUseCase.preserveFailedImages(sources, id: id, roomID: room.id,
                        senderUID: self.chatRoomViewModel.currentUserUID)
                }
            }, onCommitted: { id in
                committedIDs.append(id)
            })
            if rejected > 0, !mediaSessionStopped {
                AlertManager.showAlertNoHandler(title: "사진을 전송하지 못했어요",
                    message: "전송하지 못한 사진은 실패 메시지에서 다시 시도하거나 삭제할 수 있어요.", viewController: self)
            }
        } catch {
            #if DEBUG
            let failure = error as NSError
            print("[MediaQA] event=selection_prepare_failed selectionID=\(selection.selectionID) domain=\(failure.domain) code=\(failure.code)")
            #endif
            // 확보 완료 선택은 durable 원본을 남겨 다음 진입의 대표 실패 버블로 복원한다.
        }
        // 최종 묶음을 선택 순서대로 모두 표시·보존한 다음 FIFO에 넣는다.
        if !committedIDs.isEmpty { await finishStagedMediaPresentation() }
        await mediaUploadUseCase.registerProcessingBatches(uploadIDs: committedIDs)
        for id in committedIDs {
            await startPreservedSelectionChunk(id, selectionID: selection.selectionID, room: room)
        }
        if !mediaSessionStopped { await restoreMediaSelections(room: room) }
    }

    private func startPreservedSelectionChunk(_ id: String, selectionID: String, room: ChatRoom) async {
        guard let payload = await outgoingOutboxUseCase.retryPayload(messageID: id, room: room) else {
            await mediaUploadUseCase.finishImageUploadTurn(uploadID: id)
            return
        }
        let stopped = mediaSessionStopped || mediaFailedSelectionIDs.contains(selectionID) || Task.isCancelled
        switch payload {
        case .uploadImages(_, _, let pairs):
            _ = stagePendingImageMessage(room: room, roomID: room.id, messageID: id, pairs: pairs)
            if stopped {
                setPendingImageUploadState(.failed, for: id)
                await mediaUploadUseCase.finishImageUploadTurn(uploadID: id)
            } else { schedulePendingImageUpload(roomID: room.id, messageID: id, pairs: pairs) }
        case .uploadVideo(_, _, let video):
            _ = stagePendingVideoMessage(roomID: room.id, messageID: id, prepared: video)
            if stopped {
                setPendingVideoUploadState(.failed, for: id)
                await mediaUploadUseCase.finishVideoUploadTurn(uploadID: id)
            } else { schedulePendingVideoUpload(roomID: room.id, messageID: id, prepared: video) }
        default: await mediaUploadUseCase.finishImageUploadTurn(uploadID: id)
        }
    }

    func stopMediaSelectionSession(reason: String = #function) {
        #if DEBUG
        for id in mediaSelectionTasks.keys {
            print("[MediaQA] event=selection_stop_requested selectionID=\(id) reason=\(reason) uptime=\(ProcessInfo.processInfo.systemUptime)")
        }
        #endif
        mediaSessionStopped = true
        mediaSelectionTasks.values.forEach { $0.cancel() }
        pendingMediaUploadStore.cancelAllTasks()
        for id in pendingMediaUploadStore.activeMessageIDs {
            if pendingMediaUploadStore.imageUploadState(for: id) != nil { setPendingImageUploadState(.failed, for: id) }
            if pendingMediaUploadStore.videoUploadState(for: id) != nil { setPendingVideoUploadState(.failed, for: id) }
        }
    }

    func failMediaNetworkSession(_ error: Error) {
        guard ChatMediaTransportFailurePolicy.isTransient(error) else { return }
        mediaNetworkFailed = true
        mediaFailedSelectionIDs.formUnion(mediaSelectionTasks.keys)
        pendingMediaUploadStore.cancelAllTasks()
        for id in pendingMediaUploadStore.activeMessageIDs {
            if pendingMediaUploadStore.imageUploadState(for: id) != nil { setPendingImageUploadState(.failed, for: id) }
            if pendingMediaUploadStore.videoUploadState(for: id) != nil { setPendingVideoUploadState(.failed, for: id) }
        }
        // 선택 준비 Task는 계속 실행해 남은 사진을 실패 묶음으로 보존한다.
    }

    func canRestartMedia(messageID: String, roomID: String) async -> Bool {
        guard let session = await outgoingOutboxUseCase.mediaSessionPayload(messageID: messageID) else { return true }
        do {
            let status = try await mediaUploadUseCase.mediaProcessingStatus(roomID: roomID,
                uploadID: session.uploadID, clientMutationID: session.clientMutationID)
            switch status.processingStatus {
            case .ready, .queued, .processing:
                resumeStatusMonitoring(roomID: roomID, messageID: messageID, clientMutationID: session.clientMutationID,
                    isVideo: session.kind == "video", snapshot: status)
                return false
            case .failed, .canceled, .expired: return true
            case .uploading:
                let canceled = try await mediaUploadUseCase.cancelMediaProcessing(roomID: roomID,
                    uploadID: session.uploadID, clientMutationID: session.clientMutationID)
                if canceled.processingStatus == .ready {
                    resumeStatusMonitoring(roomID: roomID, messageID: messageID, clientMutationID: session.clientMutationID,
                        isVideo: session.kind == "video", snapshot: canceled)
                    return false
                }
                return [.canceled, .failed, .expired].contains(canceled.processingStatus)
            }
        } catch {
            guard (error as NSError).userInfo["serverErrorCode"] as? String == "media_reservation_not_found" else { return false }
            // 없음 응답만으로 새 identity를 만들지 않는다. 늦은 예약을 cancel로 차단한다.
            guard let canceled = try? await mediaUploadUseCase.cancelMediaProcessing(roomID: roomID,
                uploadID: session.uploadID, clientMutationID: session.clientMutationID) else { return false }
            return [.canceled, .failed, .expired].contains(canceled.processingStatus)
        }
    }

    func restoreMediaSelections(room: ChatRoom) async {
        let sender = chatRoomViewModel.currentUserUID
        guard let selections = try? await mediaSelectionUseCase.restoredSelections(roomID: room.id,
            senderUID: sender, excluding: Set(mediaSelectionTasks.keys).union(mediaDeletingSelectionIDs)) else { return }
        for selection in selections {
            guard !mediaSessionStopped, chatRoomViewModel.currentUserUID == sender else { return }
            // 실행 중인 선택의 대표 버블은 노출하지 않는다.
            guard mediaSelectionTasks[selection.selectionID] == nil else { continue }
            let attachments = selection.selectionSources.enumerated().map { offset, source in
                Attachment(type: source.isVideo ? .video : .image, index: offset,
                    pathThumb: source.isVideo ? "" : URL(fileURLWithPath: source.path).absoluteString,
                    pathOriginal: URL(fileURLWithPath: source.path).absoluteString,
                    width: 1, height: 1, bytesOriginal: 0, hash: "\(selection.selectionID)-\(source.index)")
            }
            let message = ChatMessage(ID: selection.selectionID, seq: 0, roomID: room.id,
                senderUID: sender, senderNickname: "", senderAvatarPath: nil, msg: "",
                sentAt: selection.createdAt, attachments: attachments, replyPreview: nil, isFailed: true)
            addMessages([message], updateType: .newer)
        }
    }

    func restoreMediaSession(room: ChatRoom) async {
        await restoreMediaSelections(room: room)
        // 화면 이탈 전에 ready까지 확인했지만 공개 메시지 조회만 실패한 항목을 복구한다.
        let records = await outgoingOutboxUseCase.pendingMediaRecords(roomID: room.id)
        for record in records where record.processingStatus == "ready" {
            guard !mediaSessionStopped else { return }
            if let message = try? await mediaUploadUseCase.confirmedMessage(roomID: room.id, messageID: record.messageID) {
                await handleIncomingMessage(message)
            }
        }
    }

    func retryMediaSelection(_ selection: ChatMediaSelection, room: ChatRoom) {
        guard mediaSelectionTasks[selection.selectionID] == nil else { return }
        mediaSessionStopped = false
        mediaNetworkFailed = false
        mediaFailedSelectionIDs.remove(selection.selectionID)
        mediaSelectionTasks[selection.selectionID] = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.mediaSelectionUseCase.beginSelection(selection.selectionID)
                await self.processMediaSelection(selection, room: room)
                await self.mediaSelectionUseCase.endSelection(selection.selectionID)
            } catch { }
            self.removeMessageFromWindow(messageID: selection.selectionID)
            self.mediaSelectionTasks.removeValue(forKey: selection.selectionID)
            if !self.mediaSessionStopped { await self.restoreMediaSelections(room: room) }
        }
        reconfigureMessageItem(messageID: selection.selectionID)
    }
}
