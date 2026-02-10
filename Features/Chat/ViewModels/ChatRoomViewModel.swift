//
//  ChatRoomViewModel.swift
//  OutPick
//
//  Created by Codex on 2/11/26.
//

import Foundation
import Combine

@MainActor
final class ChatRoomViewModel {
    enum LiveMode {
        case catchingUp
        case live
    }

    struct InitialLoadResult {
        let localMessages: [ChatMessage]
        let serverMessages: [ChatMessage]
        let deletedMessages: [ChatMessage]
        let isParticipant: Bool
    }

    struct NewerMessagesResult {
        let messages: [ChatMessage]
        let bufferedMessagesToFlush: [ChatMessage]
    }

    enum IncomingMessageAction {
        case buffered
        case append
    }

    private(set) var room: ChatRoom

    private let messageUseCase: ChatRoomMessageUseCaseProtocol
    private let searchUseCase: ChatRoomSearchUseCaseProtocol
    private let lifecycleUseCase: ChatRoomLifecycleUseCaseProtocol

    private(set) var isInitialLoading: Bool = true
    private(set) var isLoadingOlder: Bool = false
    private(set) var isLoadingNewer: Bool = false
    private(set) var hasMoreOlder: Bool = true
    private(set) var hasMoreNewer: Bool = true

    private(set) var filteredMessages: [ChatMessage] = []
    private(set) var currentFilteredMessageIndex: Int?
    private(set) var highlightedMessageIDs: Set<String> = []
    private(set) var currentSearchKeyword: String?

    private(set) var liveMode: LiveMode = .live
    private(set) var entryTailSeq: Int64 = 0
    private(set) var windowMaxSeq: Int64 = 0

    private var liveBuffer: [ChatMessage] = []
    private var liveBufferIDs: Set<String> = []
    private var lastSentLastReadSeq: Int64 = 0

    let minTriggerDistance: Int = 3

    init(
        room: ChatRoom,
        messageUseCase: ChatRoomMessageUseCaseProtocol,
        searchUseCase: ChatRoomSearchUseCaseProtocol,
        lifecycleUseCase: ChatRoomLifecycleUseCaseProtocol
    ) {
        self.room = room
        self.messageUseCase = messageUseCase
        self.searchUseCase = searchUseCase
        self.lifecycleUseCase = lifecycleUseCase
    }

    var roomID: String { room.ID ?? "" }
    var roomChangePublisher: AnyPublisher<ChatRoom, Never> {
        lifecycleUseCase.roomChangePublisher
    }

    func isCurrentUserParticipant(_ email: String) -> Bool {
        room.participants.contains(email)
    }

    func applyRoomUpdate(_ updatedRoom: ChatRoom) {
        room = updatedRoom
    }

    func startRoomUpdates() {
        lifecycleUseCase.startRoomUpdates(roomID: roomID)
    }

    func stopRoomUpdates() {
        lifecycleUseCase.stopRoomUpdates()
    }

    func handleRoomSaveCompleted(_ savedRoom: ChatRoom) {
        room = savedRoom
        lifecycleUseCase.handleRoomSaved(roomID: savedRoom.ID ?? "")
    }

    func joinCurrentRoom() async throws -> ChatRoom {
        let updatedRoom = try await lifecycleUseCase.joinRoom(roomID: roomID)
        room = updatedRoom
        return updatedRoom
    }

    func loadInitialMessages(isParticipant: Bool) async throws -> InitialLoadResult {
        isInitialLoading = true
        defer { isInitialLoading = false }

        let (localMessages, serverMessages) = try await messageUseCase.loadInitialMessages(room: room, isParticipant: isParticipant)

        guard isParticipant else {
            return InitialLoadResult(
                localMessages: [],
                serverMessages: serverMessages,
                deletedMessages: [],
                isParticipant: false
            )
        }

        let deletedIDs = try await messageUseCase.syncDeletedStates(localMessages: localMessages, room: room)
        let deletedMessages = localMessages
            .filter { deletedIDs.contains($0.ID) }
            .map { msg in
                var copy = msg
                copy.isDeleted = true
                return copy
            }

        entryTailSeq = Int64(room.seq)
        let localMaxSeq = localMessages.map(\.seq).max() ?? 0
        let serverMaxSeq = serverMessages.map(\.seq).max() ?? 0
        windowMaxSeq = max(localMaxSeq, serverMaxSeq)
        liveMode = (windowMaxSeq >= entryTailSeq) ? .live : .catchingUp

        return InitialLoadResult(
            localMessages: localMessages,
            serverMessages: serverMessages,
            deletedMessages: deletedMessages,
            isParticipant: true
        )
    }

    func loadOlderMessages(before messageID: String?) async throws -> [ChatMessage] {
        guard !isLoadingOlder, hasMoreOlder else { return [] }

        isLoadingOlder = true
        defer { isLoadingOlder = false }

        let loaded = try await messageUseCase.loadOlderMessages(room: room, before: messageID)
        if loaded.isEmpty {
            hasMoreOlder = false
        }
        return loaded
    }

    func loadNewerMessages(after messageID: String?) async throws -> NewerMessagesResult {
        guard !isLoadingNewer else {
            return NewerMessagesResult(messages: [], bufferedMessagesToFlush: [])
        }

        isLoadingNewer = true
        defer { isLoadingNewer = false }

        let loaded = try await messageUseCase.loadNewerMessages(room: room, after: messageID)

        if let pageMax = loaded.last?.seq, pageMax > windowMaxSeq {
            windowMaxSeq = pageMax
        }

        var bufferedMessagesToFlush: [ChatMessage] = []
        if liveMode == .catchingUp && windowMaxSeq >= entryTailSeq {
            liveMode = .live
            bufferedMessagesToFlush = flushBufferedLiveMessages()
        }

        return NewerMessagesResult(messages: loaded, bufferedMessagesToFlush: bufferedMessagesToFlush)
    }

    func handleIncomingMessage(_ message: ChatMessage) -> IncomingMessageAction {
        switch liveMode {
        case .catchingUp:
            if !liveBufferIDs.contains(message.ID) {
                liveBufferIDs.insert(message.ID)
                liveBuffer.append(message)
            }
            return .buffered

        case .live:
            if message.seq > windowMaxSeq {
                windowMaxSeq = message.seq
            }
            return .append
        }
    }

    func persistIncomingMessage(_ message: ChatMessage) async throws {
        try await messageUseCase.handleIncomingMessage(message, room: room)
    }

    func setupDeletionListener(onDeleted: @escaping (String) -> Void) -> AnyCancellable {
        messageUseCase.setupDeletionListener(roomID: roomID, onDeleted: onDeleted)
    }

    func deleteMessage(_ message: ChatMessage) async throws {
        try await messageUseCase.deleteMessage(message: message, room: room)
    }

    func searchMessages(containing keyword: String) async throws {
        filteredMessages = try await searchUseCase.searchMessages(roomID: roomID, keyword: keyword)
        currentFilteredMessageIndex = filteredMessages.isEmpty ? nil : filteredMessages.count
        currentSearchKeyword = keyword
        highlightedMessageIDs = searchUseCase.applyHighlight(messageIDs: Set(filteredMessages.map { $0.ID }))
    }

    func moveToPreviousSearchResult() -> Int? {
        guard let current = currentFilteredMessageIndex, current > 1 else {
            return currentFilteredMessageIndex
        }
        currentFilteredMessageIndex = current - 1
        return currentFilteredMessageIndex
    }

    func moveToNextSearchResult() -> Int? {
        guard let current = currentFilteredMessageIndex, current < filteredMessages.count else {
            return currentFilteredMessageIndex
        }
        currentFilteredMessageIndex = current + 1
        return currentFilteredMessageIndex
    }

    func searchMessage(at index: Int) -> ChatMessage? {
        guard index > 0 else { return nil }
        let target = index - 1
        guard filteredMessages.indices.contains(target) else { return nil }
        return filteredMessages[target]
    }

    func clearSearch() -> Set<String> {
        let previous = highlightedMessageIDs
        highlightedMessageIDs = searchUseCase.clearHighlight()
        currentSearchKeyword = nil
        currentFilteredMessageIndex = nil
        filteredMessages = []
        return previous
    }

    func isHighlightedMessage(id: String) -> Bool {
        highlightedMessageIDs.contains(id)
    }

    func saveAnnouncement(message: ChatMessage, authorID: String) async throws {
        let payload = AnnouncementPayload(
            text: message.msg ?? "",
            authorID: authorID,
            createdAt: Date()
        )
        try await lifecycleUseCase.setActiveAnnouncement(
            roomID: roomID,
            messageID: message.ID,
            payload: payload
        )
    }

    func clearAnnouncement() async throws {
        try await lifecycleUseCase.clearActiveAnnouncement(roomID: roomID)
    }

    func finalLastReadSeqForSessionEnd() -> Int64 {
        let finalSeq = min(windowMaxSeq, entryTailSeq)
        if finalSeq > lastSentLastReadSeq {
            lastSentLastReadSeq = finalSeq
        }
        return finalSeq
    }

    func persistFinalLastReadSeq(userID: String) async throws {
        let finalSeq = finalLastReadSeqForSessionEnd()
        try await lifecycleUseCase.updateLastReadSeq(
            roomID: roomID,
            userID: userID,
            lastReadSeq: finalSeq
        )
    }

    func nextLastReadSeqCandidate(isNearBottom: Bool, skipNearBottomCheck: Bool) -> Int64? {
        if !skipNearBottomCheck, !isNearBottom {
            return nil
        }

        let candidate = min(windowMaxSeq, entryTailSeq)
        guard candidate > lastSentLastReadSeq else { return nil }

        lastSentLastReadSeq = candidate
        return candidate
    }

    func persistIncrementalLastReadSeq(
        userID: String,
        isNearBottom: Bool,
        skipNearBottomCheck: Bool
    ) async throws {
        guard let seq = nextLastReadSeqCandidate(
            isNearBottom: isNearBottom,
            skipNearBottomCheck: skipNearBottomCheck
        ) else { return }
        try await lifecycleUseCase.updateLastReadSeq(
            roomID: roomID,
            userID: userID,
            lastReadSeq: seq
        )
    }

    private func flushBufferedLiveMessages() -> [ChatMessage] {
        guard !liveBuffer.isEmpty else { return [] }

        let sorted = liveBuffer.sorted { $0.seq < $1.seq }
        liveBuffer.removeAll()
        liveBufferIDs.removeAll()

        if let maxSeq = sorted.map(\.seq).max(), maxSeq > windowMaxSeq {
            windowMaxSeq = maxSeq
        }

        return sorted
    }
}
