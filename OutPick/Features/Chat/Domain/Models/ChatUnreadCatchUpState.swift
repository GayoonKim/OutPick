//
//  ChatUnreadCatchUpState.swift
//  OutPick
//
//  Created by Codex on 7/17/26.
//

import Foundation

struct ChatLatestMessageWindow: Equatable {
    static let maximumMessageCount = 80

    let targetSeq: Int64
    let messages: [ChatMessage]

    static func query(for targetSeq: Int64) throws -> ChatLatestMessageWindowQuery {
        guard targetSeq > 0 else { throw ChatLatestMessageWindowError.invalidTarget }
        if targetSeq == Int64.max {
            return .latest(limit: maximumMessageCount)
        }
        return .beforeSeq(targetSeq + 1, limit: maximumMessageCount)
    }

    static func make(targetSeq: Int64, fetched: [ChatMessage]) throws -> ChatLatestMessageWindow {
        _ = try query(for: targetSeq)

        var seenIDs = Set<String>()
        let messages = Array(
            fetched
                .filter { $0.seq > 0 && $0.seq <= targetSeq && seenIDs.insert($0.ID).inserted }
                .sorted { lhs, rhs in
                    if lhs.seq != rhs.seq { return lhs.seq < rhs.seq }
                    return lhs.ID < rhs.ID
                }
                .suffix(maximumMessageCount)
        )
        guard messages.contains(where: { $0.seq == targetSeq }) else {
            throw ChatLatestMessageWindowError.targetMissing
        }
        return ChatLatestMessageWindow(targetSeq: targetSeq, messages: messages)
    }
}

enum ChatLatestMessageWindowQuery: Equatable {
    case beforeSeq(Int64, limit: Int)
    case latest(limit: Int)
}

enum ChatLatestMessageWindowError: LocalizedError, Equatable {
    case invalidTarget
    case targetMissing

    var errorDescription: String? {
        switch self {
        case .invalidTarget:
            return "최신 메시지 target이 유효하지 않습니다."
        case .targetMissing:
            return "최신 메시지 target을 조회 결과에서 찾지 못했습니다."
        }
    }
}

struct ChatLatestJumpRequest: Equatable {
    let generation: UInt64
    let targetSeq: Int64
}

enum ChatLatestMessagePreviewKind: Equatable {
    case text
    case image
    case video
    case lookbook
    case generic
}

enum ChatLatestMessagePreviewImageSource: Equatable {
    case avatar(String)
    case attachment(String)
}

struct ChatLatestMessagePreview: Equatable {
    let targetSeq: Int64
    let senderName: String?
    let text: String
    let kind: ChatLatestMessagePreviewKind
    let imageSource: ChatLatestMessagePreviewImageSource?

    static func generic(
        targetSeq: Int64,
        senderName: String? = nil,
        text: String? = nil
    ) -> Self {
        Self(
            targetSeq: targetSeq,
            senderName: normalizedText(senderName),
            text: normalizedText(text) ?? "새 메시지가 도착했어요",
            kind: inferredKind(from: text),
            imageSource: nil
        )
    }

    static func make(from message: ChatMessage) -> Self {
        let senderName = normalizedText(message.senderNickname)
        let text = normalizedText(message.previewTextForRoomList) ?? "새 메시지가 도착했어요"

        if let sharedContent = message.sharedContent {
            let path = normalizedText(sharedContent.thumbnailPathSnapshot)
            return Self(
                targetSeq: message.seq,
                senderName: senderName,
                text: text,
                kind: .lookbook,
                imageSource: path.map(ChatLatestMessagePreviewImageSource.attachment)
            )
        }

        if let attachment = message.attachments.sorted(by: { $0.index < $1.index }).first {
            let path = normalizedText(attachment.preferredDisplayPath)
            return Self(
                targetSeq: message.seq,
                senderName: senderName,
                text: text,
                kind: attachment.type == .video ? .video : .image,
                imageSource: path.map(ChatLatestMessagePreviewImageSource.attachment)
            )
        }

        let avatarPath = normalizedText(message.senderAvatarPath)
        return Self(
            targetSeq: message.seq,
            senderName: senderName,
            text: text,
            kind: .text,
            imageSource: avatarPath.map(ChatLatestMessagePreviewImageSource.avatar)
        )
    }

    private static func inferredKind(from text: String?) -> ChatLatestMessagePreviewKind {
        guard let text = normalizedText(text) else { return .generic }
        if text.hasPrefix("사진") { return .image }
        if text.hasPrefix("동영상") { return .video }
        if text.contains("룩북") { return .lookbook }
        return .text
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

struct ChatLatestJumpPresentation: Equatable {
    let isVisible: Bool
    let isLoading: Bool
    let preview: ChatLatestMessagePreview?
    let unreadAccessibilityText: String?
}

struct ChatUnreadCatchUpState: Equatable {
    private(set) var knownLatestSeq: Int64
    private(set) var readFrontierSeq: Int64
    private(set) var latestPreview: ChatLatestMessagePreview?
    private(set) var jumpPreview: ChatLatestMessagePreview?
    private(set) var jumpTargetSeq: Int64?
    private(set) var jumpGeneration: UInt64
    private(set) var isJumpLoading: Bool

    init(
        knownLatestSeq: Int64 = 0,
        readFrontierSeq: Int64 = 0,
        latestPreview: ChatLatestMessagePreview? = nil
    ) {
        let normalizedFrontier = max(Int64(0), readFrontierSeq)
        self.readFrontierSeq = normalizedFrontier
        self.knownLatestSeq = max(normalizedFrontier, knownLatestSeq)
        self.latestPreview = latestPreview?.targetSeq == self.knownLatestSeq
            ? latestPreview
            : nil
        self.jumpPreview = nil
        self.jumpTargetSeq = nil
        self.jumpGeneration = 0
        self.isJumpLoading = false
    }

    var unreadCount: Int64 {
        max(Int64(0), knownLatestSeq - readFrontierSeq)
    }

    var canBeginLatestJump: Bool {
        !isJumpLoading
            && knownLatestSeq > readFrontierSeq
            && latestPreview?.targetSeq == knownLatestSeq
    }

    var presentedPreview: ChatLatestMessagePreview? {
        isJumpLoading ? jumpPreview : latestPreview
    }

    func isCurrentJump(_ request: ChatLatestJumpRequest) -> Bool {
        isJumpLoading
            && jumpGeneration == request.generation
            && jumpTargetSeq == request.targetSeq
    }

    mutating func observeLatestSeq(_ seq: Int64) {
        guard seq > knownLatestSeq else { return }
        knownLatestSeq = seq
        latestPreview = nil
    }

    mutating func observeLatestMessage(_ message: ChatMessage) {
        guard message.seq >= knownLatestSeq else { return }
        knownLatestSeq = message.seq
        latestPreview = ChatLatestMessagePreview.make(from: message)
    }

    mutating func syncReadFrontier(_ seq: Int64) {
        guard seq > readFrontierSeq else { return }
        readFrontierSeq = seq
        knownLatestSeq = max(knownLatestSeq, seq)
        if let previewTargetSeq = latestPreview?.targetSeq,
           readFrontierSeq >= previewTargetSeq {
            latestPreview = nil
        }
    }

    @discardableResult
    mutating func dismissRealtimePreview(targetSeq: Int64) -> Bool {
        guard latestPreview?.targetSeq == targetSeq else { return false }
        latestPreview = nil
        return true
    }

    mutating func clearRealtimePreview() {
        latestPreview = nil
    }

    mutating func beginLatestJump() -> ChatLatestJumpRequest? {
        guard canBeginLatestJump else { return nil }

        jumpGeneration = nextGeneration(after: jumpGeneration)
        jumpTargetSeq = knownLatestSeq
        jumpPreview = latestPreview?.targetSeq == knownLatestSeq
            ? latestPreview
            : ChatLatestMessagePreview.generic(targetSeq: knownLatestSeq)
        isJumpLoading = true

        return ChatLatestJumpRequest(
            generation: jumpGeneration,
            targetSeq: knownLatestSeq
        )
    }

    mutating func completeLatestJump(
        generation: UInt64,
        didDisplayTarget: Bool
    ) -> Int64? {
        guard isCurrentJump(generation: generation),
              let targetSeq = jumpTargetSeq else {
            return nil
        }

        clearJump()
        return didDisplayTarget ? targetSeq : nil
    }

    @discardableResult
    mutating func failLatestJump(generation: UInt64) -> Bool {
        guard isCurrentJump(generation: generation) else { return false }
        clearJump()
        return true
    }

    mutating func cancelLatestJump() {
        guard isJumpLoading else { return }
        clearJump()
        jumpGeneration = nextGeneration(after: jumpGeneration)
    }

    private func isCurrentJump(generation: UInt64) -> Bool {
        isJumpLoading && jumpGeneration == generation
    }

    private mutating func clearJump() {
        jumpPreview = nil
        jumpTargetSeq = nil
        isJumpLoading = false
    }

    private func nextGeneration(after generation: UInt64) -> UInt64 {
        generation == .max ? 1 : generation + 1
    }
}
