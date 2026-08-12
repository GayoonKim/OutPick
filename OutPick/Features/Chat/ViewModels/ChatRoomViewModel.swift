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
    enum LiveMode: Equatable {
        case catchingUp
        case live
    }

    struct NewerMessagesResult {
        let messages: [ChatMessage]
    }

    enum IncomingMessageAction: Equatable {
        case persistOnly
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
    private let userBlockVisibilityStore: any UserBlockVisibilityChecking
    private let blockUserUseCase: (any BlockUserUseCaseProtocol)?
    private let memberModerationUseCase: ChatRoomMemberModerationUseCaseProtocol?

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

    private var readStateStore = ChatReadStateStore()
    private(set) var unreadCatchUpState = ChatUnreadCatchUpState()
    private var lastReadFlushTask: Task<Void, Never>?
    private var searchMessagesTask: Task<Void, Never>?
    private var searchGeneration: Int = 0
    private var olderRawCursor: String?
    private var newerRawCursor: String?
    private var admittedHiddenSeqs = Set<Int64>()
    private let lastReadFlushDebounceNanoseconds: UInt64 = 3_000_000_000

    let minTriggerDistance: Int = 3

    var latestJumpPresentation: ChatLatestJumpPresentation {
        let unreadCount = unreadCatchUpState.unreadCount
        let preview = unreadCatchUpState.presentedPreview
        let isVisible = isCurrentUserParticipant
            && unreadCount > 0
            && preview != nil
        return ChatLatestJumpPresentation(
            isVisible: isVisible,
            isLoading: unreadCatchUpState.isJumpLoading,
            preview: preview,
            unreadAccessibilityText: isVisible
                ? "읽지 않은 메시지 \(unreadCount)개"
                : nil
        )
    }

    var readFrontierSeq: Int64 {
        readStateStore.frontierSeq
    }

    var realtimePreviewTargetSeq: Int64? {
        unreadCatchUpState.latestPreview?.targetSeq
    }

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
        roomReadStateStore: ChatRoomReadStateStore? = nil,
        userBlockVisibilityStore: any UserBlockVisibilityChecking = UserBlockVisibilityStore(),
        blockUserUseCase: (any BlockUserUseCaseProtocol)? = nil,
        memberModerationUseCase: ChatRoomMemberModerationUseCaseProtocol? = nil
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
        self.userBlockVisibilityStore = userBlockVisibilityStore
        self.blockUserUseCase = blockUserUseCase
        self.memberModerationUseCase = memberModerationUseCase
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

    func loadMyRoomAccess() async throws -> ChatRoomAccessStatus {
        guard let memberModerationUseCase else {
            return isCurrentUserParticipant ? .member : .joinable
        }
        return try await memberModerationUseCase.loadMyRoomAccess(roomID: roomID)
    }

    func removeRoomMember(targetUID: String, reason: ChatRoomMemberRemovalReason) async throws {
        guard let memberModerationUseCase else {
            throw CloudFunctionsClientError.invalidResponse
        }
        _ = try await memberModerationUseCase.removeMember(
            roomID: roomID,
            targetUID: targetUID,
            reasonCode: reason.rawValue
        )
    }

    func makeOutgoingTextMessage(text: String, replyPreview: ReplyPreview?) -> ChatMessage? {
        messageUseCase.makeTextMessage(text: text, replyPreview: replyPreview, room: room)
    }

    func sendPreparedMessage(_ message: ChatMessage) async throws -> ChatMessageSendReceipt {
        try await messageUseCase.sendPreparedMessage(message, room: room)
    }

    func openMessageStream(
        roomID: String,
        baselineSeq: Int64
    ) async throws -> ChatRoomRealtimeSession {
        try await realtimeUseCase.openMessageStream(
            roomID: roomID,
            baselineSeq: baselineSeq
        )
    }

    func observeRoomClosed(onClosed: @escaping (RealtimeRoomClosureEvent) -> Void) -> ChatRoomRuntimeSubscription? {
        guard !roomID.isEmpty else { return nil }
        return runtimeUseCase.observeRoomClosed(roomID: roomID, onClosed: onClosed)
    }

    func observeRoomMembershipRemoved(
        onRemoved: @escaping (RealtimeRoomMembershipRemovalEvent) -> Void
    ) -> ChatRoomRuntimeSubscription? {
        guard !roomID.isEmpty else { return nil }
        return runtimeUseCase.observeRoomMembershipRemoved(roomID: roomID, onRemoved: onRemoved)
    }

    func handleCurrentUserMembershipRemoved() {
        joinedRoomsStore?.remove(roomID)
    }

    func handleRoomWillAppear() {
        runtimeUseCase.enterVisibleRoom(roomID: roomID)
    }

    func handleRoomWillDisappear() {
        runtimeUseCase.leaveVisibleRoom(roomID: roomID)
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
                self.admittedHiddenSeqs.removeAll()
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

        var cursor = olderRawCursor ?? messageID
        // 차단 메시지만 이어지는 긴 구간을 한 번의 스크롤로 끝까지 조회하지 않는다.
        // 원본 커서는 계속 전진하므로 다음 페이지 요청에서 자연스럽게 이어진다.
        for _ in 0..<3 where hasMoreOlder {
            let loaded = try await messageUseCase.loadOlderMessages(room: room, before: cursor)
            guard !loaded.isEmpty else {
                hasMoreOlder = false
                return []
            }
            guard let nextCursor = loaded.first?.ID, nextCursor != cursor else {
                hasMoreOlder = false
                return admitVisibleMessages(from: loaded)
            }
            cursor = nextCursor
            olderRawCursor = nextCursor
            let visible = admitVisibleMessages(from: loaded)
            if !visible.isEmpty { return visible }
        }
        return []
    }

    func loadNewerMessages(after messageID: String?) async throws -> NewerMessagesResult {
        guard !isLoadingNewer else {
            return NewerMessagesResult(messages: [])
        }

        isLoadingNewer = true
        defer { isLoadingNewer = false }

        var cursor = newerRawCursor ?? messageID
        // 새 메시지 방향도 한 번에 조회하는 원본 페이지 수를 제한한다.
        for _ in 0..<3 where hasMoreNewer {
            let loaded = try await messageUseCase.loadNewerMessages(room: room, after: cursor)
            guard !loaded.isEmpty else {
                hasMoreNewer = false
                return NewerMessagesResult(messages: [])
            }
            guard let nextCursor = loaded.last?.ID, nextCursor != cursor else {
                hasMoreNewer = false
                return NewerMessagesResult(messages: admitVisibleMessages(from: loaded))
            }
            cursor = nextCursor
            newerRawCursor = nextCursor
            if let pageMax = loaded.last?.seq, pageMax > windowMaxSeq {
                windowMaxSeq = pageMax
            }
            if liveMode == .catchingUp && windowMaxSeq >= unreadCatchUpState.knownLatestSeq {
                liveMode = .live
                hasMoreNewer = false
            }
            let visible = admitVisibleMessages(from: loaded)
            if !visible.isEmpty || !hasMoreNewer {
                return NewerMessagesResult(messages: visible)
            }
        }
        return NewerMessagesResult(messages: [])
    }

    func loadLatestMessageWindow(targetSeq: Int64) async throws -> ChatLatestMessageWindow {
        try await messageUseCase.loadLatestMessageWindow(room: room, targetSeq: targetSeq)
    }

    func beginLatestJump() -> ChatLatestJumpRequest? {
        unreadCatchUpState.beginLatestJump()
    }

    func isCurrentLatestJump(_ request: ChatLatestJumpRequest) -> Bool {
        unreadCatchUpState.isCurrentJump(request)
    }

    @discardableResult
    func completeLatestJump(
        _ request: ChatLatestJumpRequest,
        didDisplayTarget: Bool
    ) -> Bool {
        guard let approvedTarget = unreadCatchUpState.completeLatestJump(
            generation: request.generation,
            didDisplayTarget: didDisplayTarget
        ) else {
            return false
        }

        _ = readStateStore.queueExplicitJumpTarget(approvedTarget)
        unreadCatchUpState.syncReadFrontier(approvedTarget)
        windowMaxSeq = approvedTarget
        liveMode = approvedTarget >= unreadCatchUpState.knownLatestSeq ? .live : .catchingUp
        hasMoreOlder = true
        hasMoreNewer = liveMode == .catchingUp
        return true
    }

    @discardableResult
    func failLatestJump(_ request: ChatLatestJumpRequest) -> Bool {
        unreadCatchUpState.failLatestJump(generation: request.generation)
    }

    func cancelLatestJump() {
        unreadCatchUpState.cancelLatestJump()
    }

    @discardableResult
    func dismissRealtimePreview(targetSeq: Int64) -> Bool {
        unreadCatchUpState.dismissRealtimePreview(targetSeq: targetSeq)
    }

    func clearRealtimePreview() {
        unreadCatchUpState.clearRealtimePreview()
    }

    @discardableResult
    func recordVisibleMessage(
        highestVisibleSeq: Int64,
        contiguousLoadedThroughSeq: Int64
    ) -> Int64? {
        guard let candidate = readStateStore.queueVisibleCandidate(
            highestVisibleSeq,
            contiguousLoadedThroughSeq: contiguousLoadedThroughSeq
        ) else {
            return nil
        }

        unreadCatchUpState.syncReadFrontier(candidate)
        scheduleDebouncedLastReadFlush(userUID: currentUserDocumentID)
        return candidate
    }

    func handleIncomingMessage(_ message: ChatMessage) -> IncomingMessageAction {
        seedRoomReadLatest(from: message)
        unreadCatchUpState.observeLatestMessage(message)

        switch liveMode {
        case .catchingUp:
            return .persistOnly

        case .live:
            if message.seq > windowMaxSeq {
                windowMaxSeq = message.seq
            }
            return .append
        }
    }

    func shouldAdmitMessage(_ message: ChatMessage) -> Bool {
        !userBlockVisibilityStore.isBlocked(message.senderUID)
    }

    func visibleMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter(shouldAdmitMessage)
    }

    func admitVisibleMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        for message in messages where !shouldAdmitMessage(message) && message.seq > 0 {
            admittedHiddenSeqs.insert(message.seq)
        }
        return visibleMessages(from: messages)
    }

    func contiguousLoadedThroughSeq(
        visibleLoadedSeqs: Set<Int64>,
        after frontierSeq: Int64
    ) -> Int64 {
        var contiguous = max(Int64(0), frontierSeq)
        while contiguous < Int64.max {
            let next = contiguous + 1
            guard visibleLoadedSeqs.contains(next) || admittedHiddenSeqs.contains(next) else {
                break
            }
            contiguous += 1
        }
        return contiguous
    }

    func consumeHiddenLiveMessage(_ message: ChatMessage) {
        guard message.seq > 0 else { return }
        admittedHiddenSeqs.insert(message.seq)
        guard liveMode == .live, message.seq == readStateStore.frontierSeq + 1 else { return }
        seedRoomReadLatest(from: message)
        windowMaxSeq = max(windowMaxSeq, message.seq)
        if let candidate = readStateStore.queueVisibleCandidate(
            message.seq,
            contiguousLoadedThroughSeq: message.seq
        ) {
            unreadCatchUpState.syncReadFrontier(candidate)
            scheduleDebouncedLastReadFlush(userUID: currentUserDocumentID)
        }
    }

    func isBlockedUser(_ userID: String) -> Bool {
        userBlockVisibilityStore.isBlocked(userID)
    }

    func blockMessageAuthor(_ message: ChatMessage) async throws {
        guard let blockUserUseCase else { return }
        _ = try await blockUserUseCase.execute(
            blockerUserID: UserID(value: currentUserUID),
            blockedUserID: UserID(value: message.senderUID),
            blockedUserNicknameSnapshot: message.senderNickname,
            source: .chat
        )
    }

    func applyInitialMessageSyncState(_ state: ChatInitialSessionState) {
        entryTailSeq = state.latestSeq
        windowMaxSeq = state.windowMaxSeq
        initialReadBoundarySeq = state.readBoundarySeq
        hasMoreOlder = state.hasMoreOlder
        hasMoreNewer = state.hasMoreNewer
        olderRawCursor = nil
        newerRawCursor = nil
        liveMode = (windowMaxSeq >= entryTailSeq) ? .live : .catchingUp
        let persistedFrontier = state.readBoundarySeq ?? 0
        readStateStore.reset(persistedLastReadSeq: persistedFrontier)
        unreadCatchUpState = ChatUnreadCatchUpState(
            knownLatestSeq: state.latestSeq,
            readFrontierSeq: persistedFrontier
        )
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
        let hits = result.hits.filter { shouldAdmitMessage($0.message) }
        searchSession = SearchSessionState(
            keyword: result.keyword,
            totalCount: hits.count,
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
        let messages = try await messageUseCase.loadMessagesAroundAnchor(
            room: room,
            anchor: anchor,
            beforeLimit: beforeLimit,
            afterLimit: afterLimit
        )
        return visibleMessages(from: messages)
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
            authorUID: currentUserUID,
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

    func visibleAnnouncement(_ payload: AnnouncementPayload?) -> AnnouncementPayload? {
        guard let payload else { return nil }
        guard let authorUID = payload.authorUID else { return payload }
        return userBlockVisibilityStore.isBlocked(authorUID) ? nil : payload
    }

    func finalLastReadSeqForSessionEnd() -> Int64 {
        readStateStore.finalSeqForSessionEnd()
    }

    func persistFinalLastReadSeq(userUID: String) async throws {
        let finalSeq = finalLastReadSeqForSessionEnd()
        readStateStore.queue(finalSeq)
        lastReadFlushTask?.cancel()
        lastReadFlushTask = nil
        try await flushPendingLastReadSeq(userUID: userUID)
    }

    func persistFinalLastReadSeqForCurrentUser() async throws {
        try await persistFinalLastReadSeq(userUID: currentUserDocumentID)
    }

    func persistExplicitLatestJumpForCurrentUser() async throws {
        lastReadFlushTask?.cancel()
        lastReadFlushTask = nil
        let userUID = currentUserDocumentID
        let requestedSeq = readStateStore.pendingFlushSeq()
        print(
            "[ChatReadPersistence][explicit-preflight] "
                + "room=\(maskedIdentifier(roomID)) "
                + "user=\(maskedIdentifier(userUID)) "
                + "requested=\(requestedSeq.map(String.init) ?? "nil") "
                + "pending=\(readStateStore.pendingLastReadSeq) "
                + "persisted=\(readStateStore.persistedLastReadSeq) "
                + "frontier=\(readStateStore.frontierSeq)"
        )
        try await flushPendingLastReadSeq(userUID: userUID)
        print(
            "[ChatReadPersistence][explicit-write-success] "
                + "room=\(maskedIdentifier(roomID)) "
                + "user=\(maskedIdentifier(userUID)) "
                + "requested=\(requestedSeq.map(String.init) ?? "nil")"
        )
        do {
            let authoritativeSeq = try await lifecycleUseCase.fetchAuthoritativeLastReadSeq(
                roomID: roomID,
                userUID: userUID
            )
            print(
                "[ChatReadPersistence][explicit-readback] "
                    + "room=\(maskedIdentifier(roomID)) "
                    + "user=\(maskedIdentifier(userUID)) "
                    + "requested=\(requestedSeq.map(String.init) ?? "nil") "
                    + "authoritative=\(authoritativeSeq.map(String.init) ?? "unsupported")"
            )
        } catch {
            print(
                "[ChatReadPersistence][explicit-readback-failure] "
                    + "room=\(maskedIdentifier(roomID)) "
                    + "user=\(maskedIdentifier(userUID)) error=\(error)"
            )
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

    private func maskedIdentifier(_ value: String) -> String {
        guard value.count > 4 else { return "***" }
        return "\(value.prefix(2))…\(value.suffix(2))"
    }

    private func seedRoomReadLatest(from message: ChatMessage) {
        guard message.seq > 0 else { return }
        roomReadStateStore?.seedLatest(
            roomID: roomID,
            latestSeq: message.seq,
            lastMessageSenderUID: message.senderUID
        )
    }

}
