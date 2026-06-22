//
//  ChatPendingMediaUploadStore.swift
//  OutPick
//
//  Created by Codex on 6/18/26.
//

import Foundation

enum ChatPendingMediaUploadState: Equatable {
    case uploading(Double)
    case failed
}

struct ChatPendingImageUploadPayload {
    let room: ChatRoom
    let roomID: String
    let messageID: String
    let pairs: [DefaultMediaProcessingService.ImagePair]
}

enum ChatPendingMediaRetryPayload {
    case uploadImages(ChatPendingImageUploadPayload)
    case finalizeImages(room: ChatRoom, roomID: String, messageID: String, attachments: [Attachment])
    case uploadVideo(roomID: String, messageID: String, prepared: PreparedVideo)
    case finalizeVideo(roomID: String, messageID: String, payload: VideoMetaPayload)
}

@MainActor
final class ChatPendingMediaUploadStore {
    private struct PendingImageUploadRecord {
        let room: ChatRoom
        let roomID: String
        let messageID: String
        let pairs: [DefaultMediaProcessingService.ImagePair]
        var state: ChatPendingMediaUploadState
        var task: Task<Void, Never>?
        var uploadedAttachments: [Attachment]?
    }

    private struct PendingVideoUploadRecord {
        let roomID: String
        let messageID: String
        let prepared: PreparedVideo?
        var state: ChatPendingMediaUploadState
        var task: Task<Void, Never>?
        var uploadedPayload: VideoMetaPayload?
    }

    private var imageUploads: [String: PendingImageUploadRecord] = [:]
    private var videoUploads: [String: PendingVideoUploadRecord] = [:]

    func stageImageUpload(
        room: ChatRoom,
        roomID: String,
        messageID: String,
        pairs: [DefaultMediaProcessingService.ImagePair]
    ) -> Bool {
        guard !roomID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !messageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !pairs.isEmpty else {
            return false
        }

        imageUploads[messageID] = PendingImageUploadRecord(
            room: room,
            roomID: roomID,
            messageID: messageID,
            pairs: pairs,
            state: .uploading(0),
            task: nil,
            uploadedAttachments: nil
        )
        return true
    }

    func imageUploadState(for messageID: String) -> ChatPendingMediaUploadState? {
        imageUploads[messageID]?.state
    }

    func videoUploadState(for messageID: String) -> ChatPendingMediaUploadState? {
        videoUploads[messageID]?.state
    }

    func uploadState(for messageID: String) -> ChatPendingMediaUploadState? {
        imageUploadState(for: messageID) ?? videoUploadState(for: messageID)
    }

    func setImageUploadState(_ state: ChatPendingMediaUploadState, for messageID: String) {
        guard var record = imageUploads[messageID] else { return }
        record.state = state
        imageUploads[messageID] = record
    }

    func startImageUploadTask(_ task: Task<Void, Never>, for messageID: String) -> Bool {
        guard var record = imageUploads[messageID],
              record.task == nil else {
            return false
        }
        record.task = task
        imageUploads[messageID] = record
        return true
    }

    func finishImageUploadTask(for messageID: String) {
        guard var record = imageUploads[messageID] else { return }
        record.task = nil
        imageUploads[messageID] = record
    }

    func failImageUpload(for messageID: String) {
        setImageUploadState(.failed, for: messageID)
    }

    func completeImageUpload(for messageID: String) {
        imageUploads.removeValue(forKey: messageID)
    }

    func setUploadedImageAttachments(_ attachments: [Attachment], for messageID: String) {
        guard var record = imageUploads[messageID] else { return }
        record.uploadedAttachments = attachments
        imageUploads[messageID] = record
    }

    func stageUploadedImageFinalize(
        room: ChatRoom,
        roomID: String,
        messageID: String,
        attachments: [Attachment]
    ) -> Bool {
        guard !roomID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !messageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !attachments.isEmpty else {
            return false
        }

        imageUploads[messageID] = PendingImageUploadRecord(
            room: room,
            roomID: roomID,
            messageID: messageID,
            pairs: [],
            state: .failed,
            task: nil,
            uploadedAttachments: attachments
        )
        return true
    }

    func retryPayload(for messageID: String) -> ChatPendingImageUploadPayload? {
        guard let record = imageUploads[messageID],
              record.task == nil,
              record.state == .failed,
              !record.pairs.isEmpty else {
            return nil
        }
        return ChatPendingImageUploadPayload(
            room: record.room,
            roomID: record.roomID,
            messageID: record.messageID,
            pairs: record.pairs
        )
    }

    func mediaRetryPayload(for messageID: String) -> ChatPendingMediaRetryPayload? {
        if let record = imageUploads[messageID],
           record.task == nil,
           record.state == .failed {
            if let attachments = record.uploadedAttachments, !attachments.isEmpty {
                return .finalizeImages(
                    room: record.room,
                    roomID: record.roomID,
                    messageID: record.messageID,
                    attachments: attachments
                )
            }
            if !record.pairs.isEmpty {
                return .uploadImages(ChatPendingImageUploadPayload(
                    room: record.room,
                    roomID: record.roomID,
                    messageID: record.messageID,
                    pairs: record.pairs
                ))
            }
        }

        if let record = videoUploads[messageID],
           record.task == nil,
           record.state == .failed {
            if let payload = record.uploadedPayload {
                return .finalizeVideo(
                    roomID: record.roomID,
                    messageID: record.messageID,
                    payload: payload
                )
            }
            if let prepared = record.prepared {
                return .uploadVideo(
                    roomID: record.roomID,
                    messageID: record.messageID,
                    prepared: prepared
                )
            }
        }

        return nil
    }

    func cancelAllTasks() {
        for record in imageUploads.values {
            record.task?.cancel()
        }
        for record in videoUploads.values {
            record.task?.cancel()
        }
    }

    func removeAll() {
        imageUploads.removeAll()
        videoUploads.removeAll()
    }

    func stageVideoUpload(
        roomID: String,
        messageID: String,
        prepared: PreparedVideo
    ) -> Bool {
        guard !roomID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !messageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        videoUploads[messageID] = PendingVideoUploadRecord(
            roomID: roomID,
            messageID: messageID,
            prepared: prepared,
            state: .uploading(0),
            task: nil,
            uploadedPayload: nil
        )
        return true
    }

    func stageUploadedVideoFinalize(
        roomID: String,
        messageID: String,
        payload: VideoMetaPayload
    ) -> Bool {
        guard !roomID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !messageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        videoUploads[messageID] = PendingVideoUploadRecord(
            roomID: roomID,
            messageID: messageID,
            prepared: nil,
            state: .failed,
            task: nil,
            uploadedPayload: payload
        )
        return true
    }

    func setVideoUploadState(_ state: ChatPendingMediaUploadState, for messageID: String) {
        guard var record = videoUploads[messageID] else { return }
        record.state = state
        videoUploads[messageID] = record
    }

    func startVideoUploadTask(_ task: Task<Void, Never>, for messageID: String) -> Bool {
        guard var record = videoUploads[messageID],
              record.task == nil else {
            return false
        }
        record.task = task
        videoUploads[messageID] = record
        return true
    }

    func finishVideoUploadTask(for messageID: String) {
        guard var record = videoUploads[messageID] else { return }
        record.task = nil
        videoUploads[messageID] = record
    }

    func completeVideoUpload(for messageID: String) {
        videoUploads.removeValue(forKey: messageID)
    }

    func setUploadedVideoPayload(_ payload: VideoMetaPayload, for messageID: String) {
        guard var record = videoUploads[messageID] else { return }
        record.uploadedPayload = payload
        videoUploads[messageID] = record
    }
}
