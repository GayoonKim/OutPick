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

    struct NewerMessagesResult {
        let messages: [ChatMessage]
        let bufferedMessagesToFlush: [ChatMessage]
    }

    enum IncomingMessageAction {
        case buffered
        case append
    }

    struct SearchSessionState {
        let keyword: String
        let totalCount: Int
        let source: ChatMessageSearchSource
        let isAuthoritative: Bool
        var hits: [ChatMessageSearchHit]   // seq ASC
        var currentIndex: Int?             // 1-based index in hits
    }

    private(set) var room: ChatRoom

    private let initialLoadUseCase: ChatInitialLoadUseCaseProtocol
    private let messageUseCase: ChatRoomMessageUseCaseProtocol
    private let searchUseCase: ChatRoomSearchUseCaseProtocol
    private let lifecycleUseCase: ChatRoomLifecycleUseCaseProtocol

    private(set) var isInitialLoading: Bool = true
    private(set) var isLoadingOlder: Bool = false
    private(set) var isLoadingNewer: Bool = false
    private(set) var hasMoreOlder: Bool = true
    private(set) var hasMoreNewer: Bool = true

    private(set) var searchSession: SearchSessionState?
    var filteredMessages: [ChatMessage] { searchSession?.hits.map(\.message) ?? [] }
    var currentFilteredMessageIndex: Int? { searchSession?.currentIndex }
    var currentSearchResultCount: Int { searchSession?.totalCount ?? 0 }
    var currentSearchSource: ChatMessageSearchSource? { searchSession?.source }
    var isCurrentSearchAuthoritative: Bool { searchSession?.isAuthoritative ?? false }
    private(set) var highlightedMessageIDs: Set<String> = []
    private(set) var currentSearchKeyword: String?

    private(set) var liveMode: LiveMode = .live
    private(set) var entryTailSeq: Int64 = 0
    private(set) var windowMaxSeq: Int64 = 0
    private(set) var initialReadBoundarySeq: Int64? = nil

    private var liveBuffer: [ChatMessage] = []
    private var liveBufferIDs: Set<String> = []
    private var pendingLastReadSeq: Int64 = 0
    private var queuedLastReadSeq: Int64 = 0
    private var persistedLastReadSeq: Int64 = 0
    private var lastReadFlushTask: Task<Void, Never>?
    private let lastReadFlushDebounceNanoseconds: UInt64 = 3_000_000_000

    let minTriggerDistance: Int = 3

    init(
        room: ChatRoom,
        initialLoadUseCase: ChatInitialLoadUseCaseProtocol,
        messageUseCase: ChatRoomMessageUseCaseProtocol,
        searchUseCase: ChatRoomSearchUseCaseProtocol,
        lifecycleUseCase: ChatRoomLifecycleUseCaseProtocol
    ) {
        self.room = room
        self.initialLoadUseCase = initialLoadUseCase
        self.messageUseCase = messageUseCase
        self.searchUseCase = searchUseCase
        self.lifecycleUseCase = lifecycleUseCase
    }

    deinit {
        lastReadFlushTask?.cancel()
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

    func startInitialLoadEvents(
        isParticipant: Bool
    ) -> AsyncStream<ChatInitialLoadEvent> {
        AsyncStream { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                self.isInitialLoading = true
                defer {
                    self.isInitialLoading = false
                    continuation.finish()
                }

                for await event in self.initialLoadUseCase.execute(room: self.room, isParticipant: isParticipant) {
                    if Task.isCancelled { return }

                    if isParticipant {
                        switch event {
                        case .participantSessionReady(let state, _):
                            self.applyInitialMessageSyncState(state)

                        default:
                            break
                        }
                    }

                    continuation.yield(event)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
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

        if loaded.isEmpty {
            hasMoreNewer = false
        }
        if let pageMax = loaded.last?.seq, pageMax > windowMaxSeq {
            windowMaxSeq = pageMax
        }

        var bufferedMessagesToFlush: [ChatMessage] = []
        if liveMode == .catchingUp && windowMaxSeq >= entryTailSeq {
            liveMode = .live
            hasMoreNewer = false
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

    private func applyInitialMessageSyncState(_ state: ChatInitialSessionState) {
        entryTailSeq = state.latestSeq
        windowMaxSeq = state.windowMaxSeq
        initialReadBoundarySeq = state.readBoundarySeq
        hasMoreOlder = state.hasMoreOlder
        hasMoreNewer = state.hasMoreNewer
        liveMode = (windowMaxSeq >= entryTailSeq) ? .live : .catchingUp
        pendingLastReadSeq = 0
        queuedLastReadSeq = 0
        persistedLastReadSeq = 0
        lastReadFlushTask?.cancel()
        lastReadFlushTask = nil
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
        let result = try await fetchSearchMessages(containing: keyword)
        applySearchResult(result)
    }

    func fetchSearchMessages(containing keyword: String) async throws -> ChatMessageSearchResult {
        try await searchUseCase.searchMessages(roomID: roomID, keyword: keyword)
    }

    func applySearchResult(_ result: ChatMessageSearchResult) {
        let hits = result.hits
        searchSession = SearchSessionState(
            keyword: result.keyword,
            totalCount: result.totalCount,
            source: result.source,
            isAuthoritative: result.isAuthoritative,
            hits: hits,
            currentIndex: hits.isEmpty ? nil : hits.count
        )
        currentSearchKeyword = result.keyword
        highlightedMessageIDs = searchUseCase.applyHighlight(
            messageIDs: Set(hits.map { $0.message.ID })
        )
    }

    func moveToPreviousSearchResult() -> Int? {
        guard var session = searchSession else { return nil }
        guard let current = session.currentIndex, current > 1 else {
            return session.currentIndex
        }
        session.currentIndex = current - 1
        searchSession = session
        return session.currentIndex
    }

    func moveToNextSearchResult() -> Int? {
        guard var session = searchSession else { return nil }
        guard let current = session.currentIndex, current < session.hits.count else {
            return session.currentIndex
        }
        session.currentIndex = current + 1
        searchSession = session
        return session.currentIndex
    }

    func searchMessage(at index: Int) -> ChatMessage? {
        guard index > 0 else { return nil }
        let target = index - 1
        guard let session = searchSession, session.hits.indices.contains(target) else { return nil }
        return session.hits[target].message
    }

    func loadMessagesAroundSearchAnchor(
        _ anchor: ChatMessage,
        beforeLimit: Int = 60,
        afterLimit: Int = 60
    ) async throws -> [ChatMessage] {
        try await messageUseCase.loadMessagesAroundAnchor(
            room: room,
            anchor: anchor,
            beforeLimit: beforeLimit,
            afterLimit: afterLimit
        )
    }

    func applyVisibleWindowAfterSearchJump(_ messages: [ChatMessage]) {
        hasMoreOlder = true
        hasMoreNewer = true

        let newWindowMax = messages.map(\.seq).max() ?? 0
        windowMaxSeq = newWindowMax
        liveMode = (windowMaxSeq >= entryTailSeq) ? .live : .catchingUp
    }

    func clearSearch() -> Set<String> {
        let previous = highlightedMessageIDs
        highlightedMessageIDs = searchUseCase.clearHighlight()
        currentSearchKeyword = nil
        searchSession = nil
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
        max(windowMaxSeq, pendingLastReadSeq, queuedLastReadSeq, persistedLastReadSeq)
    }

    func persistFinalLastReadSeq(userUID: String) async throws {
        let finalSeq = finalLastReadSeqForSessionEnd()
        queueLastReadSeq(finalSeq)
        lastReadFlushTask?.cancel()
        lastReadFlushTask = nil
        try await flushPendingLastReadSeq(userUID: userUID)
    }

    func nextLastReadSeqCandidate(isNearBottom: Bool, skipNearBottomCheck: Bool) -> Int64? {
        if !skipNearBottomCheck, !isNearBottom {
            return nil
        }

        let candidate = windowMaxSeq
        let knownMax = max(queuedLastReadSeq, persistedLastReadSeq)
        guard candidate > knownMax else { return nil }
        return candidate
    }

    func persistIncrementalLastReadSeq(
        userUID: String,
        isNearBottom: Bool,
        skipNearBottomCheck: Bool
    ) async throws {
        guard let seq = nextLastReadSeqCandidate(
            isNearBottom: isNearBottom,
            skipNearBottomCheck: skipNearBottomCheck
        ) else { return }

        queueLastReadSeq(seq)
        scheduleDebouncedLastReadFlush(userUID: userUID)
    }

    private func queueLastReadSeq(_ seq: Int64) {
        guard seq > 0 else { return }
        if seq > queuedLastReadSeq {
            queuedLastReadSeq = seq
        }
        if seq > pendingLastReadSeq {
            pendingLastReadSeq = seq
        }
    }

    private func scheduleDebouncedLastReadFlush(userUID: String) {
        guard !userUID.isEmpty else { return }

        lastReadFlushTask?.cancel()
        lastReadFlushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: self.lastReadFlushDebounceNanoseconds)
            } catch {
                return
            }
            if Task.isCancelled { return }
            do {
                try await self.flushPendingLastReadSeq(userUID: userUID)
            } catch {
                print("⚠️ debounced lastReadSeq flush 실패(roomID=\(self.roomID)): \(error)")
            }
        }
    }

    private func flushPendingLastReadSeq(userUID: String) async throws {
        guard !userUID.isEmpty else { return }

        let seqToPersist = pendingLastReadSeq
        guard seqToPersist > persistedLastReadSeq else { return }

        try await lifecycleUseCase.updateLastReadSeq(
            roomID: roomID,
            userUID: userUID,
            lastReadSeq: seqToPersist
        )
        persistedLastReadSeq = max(persistedLastReadSeq, seqToPersist)
        if pendingLastReadSeq <= persistedLastReadSeq {
            pendingLastReadSeq = 0
        }
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
