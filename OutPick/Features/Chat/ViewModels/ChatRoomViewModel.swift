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

    struct SearchDisplayState {
        let totalCount: Int
        let displayIndex: Int
        let canMoveToPrevious: Bool
        let canMoveToNext: Bool
    }

    private(set) var room: ChatRoom

    private let initialLoadUseCase: ChatInitialLoadUseCaseProtocol
    private let messageUseCase: ChatRoomMessageUseCaseProtocol
    private let realtimeUseCase: ChatRoomRealtimeUseCaseProtocol
    private let runtimeUseCase: ChatRoomRuntimeUseCaseProtocol
    private let searchUseCase: ChatRoomSearchUseCaseProtocol
    private let lifecycleUseCase: ChatRoomLifecycleUseCaseProtocol
    private let currentUserProvider: CurrentUserProviding
    private let joinedRoomsStore: JoinedRoomsSessionStoring?
    private let roomReadStateStore: ChatRoomReadStateStore?

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
    var currentSearchDisplayState: SearchDisplayState {
        guard let session = searchSession,
              let currentIndex = session.currentIndex,
              session.totalCount > 0 else {
            return SearchDisplayState(
                totalCount: 0,
                displayIndex: 0,
                canMoveToPrevious: false,
                canMoveToNext: false
            )
        }
        return SearchDisplayState(
            totalCount: session.totalCount,
            displayIndex: session.totalCount - currentIndex + 1,
            canMoveToPrevious: currentIndex > 1,
            canMoveToNext: currentIndex < session.hits.count
        )
    }
    private(set) var highlightedMessageIDs: Set<String> = []
    private(set) var currentSearchKeyword: String?

    private(set) var liveMode: LiveMode = .live
    private(set) var entryTailSeq: Int64 = 0
    private(set) var windowMaxSeq: Int64 = 0
    private(set) var initialReadBoundarySeq: Int64? = nil

    private var liveBuffer: [ChatMessage] = []
    private var liveBufferIDs: Set<String> = []
    private var readStateStore = ChatReadStateStore()
    private var lastReadFlushTask: Task<Void, Never>?
    private var searchMessagesTask: Task<Void, Never>?
    private var searchGeneration: Int = 0
    private let lastReadFlushDebounceNanoseconds: UInt64 = 3_000_000_000

    let minTriggerDistance: Int = 3

    init(
        room: ChatRoom,
        initialLoadUseCase: ChatInitialLoadUseCaseProtocol,
        messageUseCase: ChatRoomMessageUseCaseProtocol,
        searchUseCase: ChatRoomSearchUseCaseProtocol,
        lifecycleUseCase: ChatRoomLifecycleUseCaseProtocol,
        realtimeUseCase: ChatRoomRealtimeUseCaseProtocol = ChatRoomRealtimeUseCase(),
        runtimeUseCase: ChatRoomRuntimeUseCaseProtocol,
        currentUserProvider: CurrentUserProviding,
        joinedRoomsStore: JoinedRoomsSessionStoring? = nil,
        roomReadStateStore: ChatRoomReadStateStore? = nil
    ) {
        self.room = room
        self.initialLoadUseCase = initialLoadUseCase
        self.messageUseCase = messageUseCase
        self.realtimeUseCase = realtimeUseCase
        self.runtimeUseCase = runtimeUseCase
        self.searchUseCase = searchUseCase
        self.lifecycleUseCase = lifecycleUseCase
        self.currentUserProvider = currentUserProvider
        self.joinedRoomsStore = joinedRoomsStore
        self.roomReadStateStore = roomReadStateStore
        seedRoomReadLatest(from: room)
    }

    deinit {
        lastReadFlushTask?.cancel()
        searchMessagesTask?.cancel()
    }

    var roomID: String { room.id }

    var currentUserUID: String {
        currentUserProvider.canonicalUserID
    }

    var currentUserDocumentID: String {
        currentUserProvider.canonicalUserID
    }

    var currentUserNickname: String? {
        currentUserProvider.nickname
    }

    var isCurrentUserParticipant: Bool {
        isCurrentUserParticipant(in: room)
    }

    func isCurrentUserParticipant(in room: ChatRoom) -> Bool {
        let roomID = room.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !roomID.isEmpty else {
            return false
        }
        if let joinedRoomsStore {
            return joinedRoomsStore.contains(roomID)
        }
        return room.participants.contains(currentUserUID)
    }

    func isCurrentUser(_ userID: String?) -> Bool {
        (userID ?? "") == currentUserUID
    }

    func isCurrentUserAdmin(of room: ChatRoom) -> Bool {
        room.creatorUID == currentUserUID
    }

    func applyRoomUpdate(_ updatedRoom: ChatRoom) {
        room = updatedRoom
        seedRoomReadLatest(from: updatedRoom)
    }

    func handleRoomSaveCompleted(_ savedRoom: ChatRoom) {
        room = savedRoom
        seedRoomReadLatest(from: savedRoom)
        lifecycleUseCase.handleRoomSaved(roomID: savedRoom.id)
    }

    func joinCurrentRoom() async throws -> ChatRoom {
        let updatedRoom = try await lifecycleUseCase.joinRoom(roomID: roomID)
        room = updatedRoom
        seedRoomReadLatest(from: updatedRoom)
        return updatedRoom
    }

    func makeOutgoingTextMessage(text: String, replyPreview: ReplyPreview?) -> ChatMessage? {
        messageUseCase.makeTextMessage(text: text, replyPreview: replyPreview, room: room)
    }

    func sendPreparedMessage(_ message: ChatMessage) async throws {
        try await messageUseCase.sendPreparedMessage(message, room: room)
    }

    func openMessageStream(roomID: String) async throws -> ChatRoomRealtimeSession {
        try await realtimeUseCase.openMessageStream(roomID: roomID)
    }

    func observeRoomClosed(onClosed: @escaping (String) -> Void) -> ChatRoomRuntimeSubscription? {
        guard !roomID.isEmpty else { return nil }
        return runtimeUseCase.observeRoomClosed(roomID: roomID, onClosed: onClosed)
    }

    func handleRoomWillAppear() async {
        await runtimeUseCase.enterVisibleRoom(roomID: roomID)
    }

    func handleRoomWillDisappear() async {
        await runtimeUseCase.leaveVisibleRoom()
    }

    func cleanTransientLocalRoomData(roomID: String) async {
        await runtimeUseCase.cleanTransientLocalRoomData(roomID: roomID)
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
        seedRoomReadLatest(from: message)

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
        readStateStore.reset()
        roomReadStateStore?.seed(
            ChatRoomReadSnapshot(
                roomID: roomID,
                latestSeq: state.latestSeq,
                lastReadSeq: state.readBoundarySeq,
                lastMessageSenderUID: room.lastMessageSenderUID
            )
        )
        lastReadFlushTask?.cancel()
        lastReadFlushTask = nil
    }

    func persistIncomingMessage(_ message: ChatMessage) async throws {
        try await messageUseCase.handleIncomingMessage(message, room: room)
    }

    func setupDeletionListener(onDeleted: @escaping (String) -> Void) -> AnyCancellable {
        messageUseCase.setupDeletionListener(roomID: roomID, onDeleted: onDeleted)
    }

    func messageActionPolicy(for message: ChatMessage) -> ChatMessageActionPolicy {
        ChatMessageActionPolicy.make(
            for: message,
            currentUserID: currentUserUID,
            roomCreatorID: room.creatorUID
        )
    }

    func performMessageServerAction(_ action: ChatMessageServerAction, for message: ChatMessage) async throws {
        switch action {
        case .delete:
            try await deleteMessage(message)
        case .announce(let authorID):
            try await saveAnnouncement(message: message, authorID: authorID)
        }
    }

    func deleteMessage(_ message: ChatMessage) async throws {
        try await messageUseCase.deleteMessage(message: message, room: room)
    }

    func searchMessages(containing keyword: String) async throws {
        let result = try await fetchSearchMessages(containing: keyword)
        applySearchResult(result)
    }

    func startSearch(
        containing keyword: String,
        onResultApplied: @escaping @MainActor () -> Void
    ) {
        searchMessagesTask?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration

        searchMessagesTask = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let result = try await self.fetchSearchMessages(containing: keyword)
                try Task.checkCancellation()
                guard self.searchGeneration == generation else { return }
                self.applySearchResult(result)
                onResultApplied()
            } catch is CancellationError {
                return
            } catch {
                print("메시지 없음")
            }
        }
    }

    func cancelSearchWork() {
        searchMessagesTask?.cancel()
        searchMessagesTask = nil
        searchGeneration &+= 1
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
        cancelSearchWork()
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
        readStateStore.finalSeqForSessionEnd(windowMaxSeq: windowMaxSeq)
    }

    func persistFinalLastReadSeq(userUID: String) async throws {
        let finalSeq = finalLastReadSeqForSessionEnd()
        readStateStore.queue(finalSeq)
        roomReadStateStore?.markReadFlushed(roomID: roomID, lastReadSeq: finalSeq)
        lastReadFlushTask?.cancel()
        lastReadFlushTask = nil
        try await flushPendingLastReadSeq(userUID: userUID)
    }

    func persistFinalLastReadSeqForCurrentUser() async throws {
        try await persistFinalLastReadSeq(userUID: currentUserDocumentID)
    }

    func nextLastReadSeqCandidate(isNearBottom: Bool, skipNearBottomCheck: Bool) -> Int64? {
        readStateStore.nextCandidate(
            windowMaxSeq: windowMaxSeq,
            isNearBottom: isNearBottom,
            skipNearBottomCheck: skipNearBottomCheck
        )
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

        readStateStore.queue(seq)
        scheduleDebouncedLastReadFlush(userUID: userUID)
    }

    func persistIncrementalLastReadSeqForCurrentUser(
        isNearBottom: Bool,
        skipNearBottomCheck: Bool
    ) async throws {
        try await persistIncrementalLastReadSeq(
            userUID: currentUserDocumentID,
            isNearBottom: isNearBottom,
            skipNearBottomCheck: skipNearBottomCheck
        )
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

        guard let seqToPersist = readStateStore.pendingFlushSeq() else { return }

        try await lifecycleUseCase.updateLastReadSeq(
            roomID: roomID,
            userUID: userUID,
            lastReadSeq: seqToPersist
        )
        readStateStore.markFlushed(seqToPersist)
        roomReadStateStore?.markReadFlushed(roomID: roomID, lastReadSeq: seqToPersist)
    }

    private func seedRoomReadLatest(from room: ChatRoom) {
        let roomID = room.id
        guard !roomID.isEmpty else { return }
        roomReadStateStore?.seedLatest(
            roomID: roomID,
            latestSeq: room.seq,
            lastMessageSenderUID: room.lastMessageSenderUID
        )
    }

    private func seedRoomReadLatest(from message: ChatMessage) {
        guard message.seq > 0 else { return }
        roomReadStateStore?.seedLatest(
            roomID: roomID,
            latestSeq: message.seq,
            lastMessageSenderUID: message.senderUID
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
