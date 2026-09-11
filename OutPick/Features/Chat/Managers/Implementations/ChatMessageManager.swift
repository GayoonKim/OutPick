//
//  ChatMessageManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation

final class ChatMessageManager: ChatMessageManaging {
    func invalidateMessageCache(roomID: String) { cacheSession.invalidate(roomID: roomID) }
    private let messageRepository: FirebaseMessageRepositoryProtocol
    private let moderationLifecycleRepository: ChatModerationLifecycleRepositoryProtocol
    private let messagePersistence: ChatMessagePersisting
    private let profileCache: ChatProfileCachePersisting
    private let deletionSanitizer: ChatDeletionSyncUseCaseProtocol?
    private let currentAccountID: @Sendable () -> String
    private let profileDisplayCacheLimit = 20
    private let pageLoader: ChatMessagePageLoader
    private let cacheSession: ChatMessageCacheSession
    private let accountID: String
    private var saveQueue: ChatMessageSaveQueue?
    private var confirmedReconciler: ChatServerConfirmedMessageReconciling?

    // Container 조립 중 한 번 호출하고 이후 변경하지 않는다.
    func configureConfirmedMessageSaving(queue: ChatMessageSaveQueue, reconciler: ChatServerConfirmedMessageReconciling) {
        saveQueue = queue
        confirmedReconciler = reconciler
    }
    
    init(
        messageRepository: FirebaseMessageRepositoryProtocol = FirebaseRepositoryProvider.shared.messageRepository,
        moderationLifecycleRepository: ChatModerationLifecycleRepositoryProtocol = CloudFunctionsChatModerationLifecycleRepository(),
        messagePersistence: ChatMessagePersisting,
        profileCache: ChatProfileCachePersisting,
        deletionSanitizer: ChatDeletionSyncUseCaseProtocol? = nil,
        cacheSession: ChatMessageCacheSession = ChatMessageCacheSession(),
        currentAccountID: @escaping @Sendable () -> String = { LoginManager.shared.canonicalUserID }
    ) {
        self.messageRepository = messageRepository
        self.moderationLifecycleRepository = moderationLifecycleRepository
        self.messagePersistence = messagePersistence
        self.profileCache = profileCache
        self.deletionSanitizer = deletionSanitizer
        self.currentAccountID = currentAccountID
        self.cacheSession = cacheSession
        self.accountID = currentAccountID()
        self.pageLoader = ChatMessagePageLoader(local: { roomID, range in
            try await messagePersistence.fetchMessagesAfterSeq(inRoom: roomID,
                afterSeq: range.lower - 1, limit: Int(range.upper - range.lower + 1))
                .filter { range.contains($0.seq) }
        }, remote: { roomID, range in
            try await messageRepository.fetchMessageRange(roomID: roomID, range: range)
        })
    }

    func loadMessagePage(_ request: ChatMessagePageRequest) async throws -> ChatMessagePageResult {
        let accountID = currentAccountID()
        let scope = cacheSession.snapshot(roomID: request.roomID)
        let result = try await pageLoader.load(request)
        guard accountID == currentAccountID(), scope.isValid(roomID: request.roomID), !Task.isCancelled else { throw CancellationError() }
        let sanitized = try await sanitizeForAdmission(result.messages, roomID: request.roomID)
        guard scope.isValid(roomID: request.roomID), accountID == currentAccountID(), !Task.isCancelled else { throw CancellationError() }
        if !result.replacedMessageIDs.isEmpty {
            // 서버 재확인으로 해소한 ID/seq 충돌만 명시적으로 교정한다.
            try await messagePersistence.saveAuthoritativeIdentityRepair(sanitized, accountID: accountID, session: scope)
        }
        // 성공한 구간은 다음 부분 재시도에서 다시 내려받지 않도록 보관한다.
        try? await persistFetchedServerMessages(sanitized)
        var admitted = try ChatMessageCacheGapPolicy.result(for: request, messages: sanitized)
        admitted.replacedMessageIDs = result.replacedMessageIDs
        return admitted
    }

    func loadLocalInitialWindow(
        roomID: String,
        mode: ChatInitialOpenMode,
        policy: ChatInitialLoadPolicy
    ) async throws -> ChatInitialWindow {
        switch mode {
        case .latestTail(let latestSeq):
            let messages = try await Task(priority: .userInitiated) {
                try await messagePersistence.fetchRecentMessages(inRoom: roomID, limit: policy.latestTailSize)
            }.value
            return try await appendingFailedOutgoingMessages(
                to: makeInitialWindow(
                messages: messages,
                readBoundarySeq: nil,
                latestSeq: latestSeq
                ),
                roomID: roomID
            )

        case .unreadAnchor(let lastReadSeq, let latestSeq):
            async let beforeMessages = messagePersistence.fetchMessagesBeforeSeq(
                inRoom: roomID,
                beforeSeq: lastReadSeq + 1,
                limit: policy.unreadBeforeContextSize
            )
            async let afterMessages = messagePersistence.fetchMessagesAfterSeq(
                inRoom: roomID,
                afterSeq: lastReadSeq,
                limit: policy.unreadAfterSize
            )

            let messages = combineAndSortInitialWindow(
                before: try await beforeMessages,
                after: try await afterMessages
            )
            return try await appendingFailedOutgoingMessages(
                to: makeInitialWindow(
                messages: messages,
                readBoundarySeq: lastReadSeq,
                latestSeq: latestSeq
                ),
                roomID: roomID
            )
        }
    }

    func fetchServerInitialWindow(
        room: ChatRoom,
        mode: ChatInitialOpenMode,
        policy: ChatInitialLoadPolicy
    ) async throws -> ChatInitialWindow {
        switch mode {
        case .latestTail(let latestSeq):
            let fetched = try await messageRepository.fetchLatestMessages(
                for: room,
                limit: policy.latestTailSize
            )
            let messages = try await sanitizeForAdmission(fetched, roomID: room.id)
            return try await appendingFailedOutgoingMessages(
                to: makeInitialWindow(
                messages: messages,
                readBoundarySeq: nil,
                latestSeq: latestSeq
                ),
                roomID: room.id
            )

        case .unreadAnchor(let lastReadSeq, let latestSeq):
            async let beforeMessages = messageRepository.fetchMessagesBeforeSeq(
                room: room,
                beforeSeq: lastReadSeq + 1,
                limit: policy.unreadBeforeContextSize
            )
            async let afterMessages = messageRepository.fetchMessagesAfterSeq(
                room: room,
                afterSeq: lastReadSeq,
                limit: policy.unreadAfterSize
            )

            let messages = try await sanitizeForAdmission(combineAndSortInitialWindow(
                before: try await beforeMessages,
                after: try await afterMessages
            ), roomID: room.id)
            return try await appendingFailedOutgoingMessages(
                to: makeInitialWindow(
                messages: messages,
                readBoundarySeq: lastReadSeq,
                latestSeq: latestSeq
                ),
                roomID: room.id
            )
        }
    }

    func persistFetchedServerMessages(_ messages: [ChatMessage]) async throws {
        guard !messages.isEmpty else { return }
        if let saveQueue {
            let reconciler = confirmedReconciler
            for message in messages {
                let scope = cacheSession.snapshot(roomID: message.roomID)
                await saveQueue.enqueue(message, save: { [self] incoming in
                    try await self.writeMessages([incoming], scope: scope)
                }, confirm: { incoming in
                    try await reconciler?.reconcileServerConfirmedMessages([incoming])
                })
            }
            return
        }
        try await writeMessages(messages)
    }

    private func writeMessages(_ messages: [ChatMessage], scope: ChatMessageCacheSession? = nil) async throws {
        try await messagePersistence.saveChatMessages(messages, accountID: accountID, session: scope ?? cacheSession)
        persistSenderDisplayCache(for: messages)
    }

    func loadMessagesAroundAnchor(
        room: ChatRoom, anchor: ChatMessage, beforeLimit: Int, afterLimit: Int
    ) async throws -> [ChatMessage] {
        let latest = try await messageRepository.fetchLatestMessages(for: room, limit: 1).first?.seq ?? anchor.seq
        let before = try ChatMessagePageRequest(roomID: room.id, direction: .older,
            boundarySeq: anchor.seq, limit: max(1, min(100, beforeLimit)), upperSeq: latest)
        let after = try ChatMessagePageRequest(roomID: room.id, direction: .newer,
            boundarySeq: anchor.seq, limit: max(1, min(100, afterLimit)), upperSeq: max(latest, anchor.seq))
        async let older = loadMessagePage(before)
        async let newer = loadMessagePage(after)
        let pages = try await (older, newer)
        return try ChatMessageMergePolicy.merge(
            (beforeLimit > 0 ? pages.0.contiguousMessages : []) + [anchor]
                + (afterLimit > 0 ? pages.1.contiguousMessages : []), roomID: room.id)
    }

    func loadOlderMessages(room: ChatRoom, before messageID: String?) async throws -> [ChatMessage] {
        guard let messageID,
              let anchor = try await messagePersistence.fetchMessage(id: messageID, inRoom: room.id) else {
            throw ChatMessagePageError.invalidRequest
        }
        let request = try ChatMessagePageRequest(roomID: room.id, direction: .older,
            boundarySeq: anchor.seq, upperSeq: max(Int64(room.seq), anchor.seq))
        return try await loadMessagePage(request).contiguousMessages
    }

    func loadNewerMessages(room: ChatRoom, after messageID: String?) async throws -> [ChatMessage] {
        guard let messageID,
              let anchor = try await messagePersistence.fetchMessage(id: messageID, inRoom: room.id) else {
            throw ChatMessagePageError.invalidRequest
        }
        let latest = try await messageRepository.fetchLatestMessages(for: room, limit: 1).first?.seq ?? anchor.seq
        let request = try ChatMessagePageRequest(roomID: room.id, direction: .newer,
            boundarySeq: anchor.seq, upperSeq: max(latest, anchor.seq))
        return try await loadMessagePage(request).contiguousMessages
    }

    func loadLatestMessageWindow(
        room: ChatRoom,
        targetSeq: Int64
    ) async throws -> ChatLatestMessageWindow {
        let query = try ChatLatestMessageWindow.query(for: targetSeq)
        let fetched: [ChatMessage]
        switch query {
        case .latest(let limit):
            let raw = try await messageRepository.fetchLatestMessages(for: room, limit: limit)
            fetched = try await sanitizeForAdmission(raw, roomID: room.id)
        case .beforeSeq(let beforeSeq, let limit):
            let raw = try await messageRepository.fetchMessagesBeforeSeq(
                room: room,
                beforeSeq: beforeSeq,
                limit: limit
            )
            fetched = try await sanitizeForAdmission(raw, roomID: room.id)
        }

        let window = try ChatLatestMessageWindow.make(targetSeq: targetSeq, fetched: fetched)
        let messages = window.messages

        try await persistFetchedServerMessages(messages)
        return window
    }
    
    func deleteMessage(message: ChatMessage, room: ChatRoom) async throws {
        let messageID = message.ID
        let roomID = room.id
        
        _ = try await moderationLifecycleRepository.deleteMessage(
            roomID: roomID,
            messageID: messageID,
            expectedSeq: message.seq,
            reasonCode: "chatMessageDeletion"
        )
        if let deletionSanitizer {
            _ = try await deletionSanitizer.reconcile(
                roomID: roomID,
                accountID: currentAccountID(),
                allowEmptyLocalBootstrap: false
            )
        }
    }
    
    func handleIncomingMessage(_ message: ChatMessage, room: ChatRoom) async throws {
        // UI admission은 호출자가 수행했고, 최신 삭제 마커는 저장 transaction에서 적용한다.
        // 재시도 횟수는 공통 저장 조정자가 단독 소유한다.
        try await persistFetchedServerMessages([message])
    }

    func sanitizeForAdmission(_ messages: [ChatMessage], roomID: String) async throws -> [ChatMessage] {
        guard let deletionSanitizer else { return messages }
        return try await deletionSanitizer.sanitize(
            messages,
            accountID: currentAccountID(),
            roomID: roomID
        )
    }

    private func persistSenderDisplayCache(for messages: [ChatMessage]) {
        let latestMessages = latestMessagesByRoomAndSender(from: messages)
        guard !latestMessages.isEmpty else { return }

        for message in latestMessages {
            let roomID = normalizedIdentifier(message.roomID)
            let senderUID = normalizedIdentifier(message.senderUID)
            guard !roomID.isEmpty,
                  !senderUID.isEmpty,
                  !roomID.contains("/"),
                  !senderUID.contains("/") else {
                continue
            }

            do {
                _ = try profileCache.upsertLocalChatUser(
                    userID: senderUID,
                    nickname: message.senderNickname,
                    profileImagePath: message.senderAvatarPath
                )
                try profileCache.upsertRoomProfileDisplayCache(
                    roomID: roomID,
                    userID: senderUID,
                    lastSeenAt: message.sentAt ?? Date(),
                    lastMessageSeq: Int(message.seq),
                    lastMessageID: message.ID,
                    maxEntriesPerRoom: profileDisplayCacheLimit
                )
            } catch {
                print("⚠️ sender display cache persistence failed:", error)
            }
        }
    }

    private func latestMessagesByRoomAndSender(from messages: [ChatMessage]) -> [ChatMessage] {
        var latestByKey: [String: ChatMessage] = [:]

        for message in messages {
            let roomID = normalizedIdentifier(message.roomID)
            let senderUID = normalizedIdentifier(message.senderUID)
            guard !roomID.isEmpty, !senderUID.isEmpty else { continue }

            let key = "\(roomID)\u{1F}\(senderUID)"
            guard let current = latestByKey[key] else {
                latestByKey[key] = message
                continue
            }

            if isMessage(message, newerThan: current) {
                latestByKey[key] = message
            }
        }

        return Array(latestByKey.values)
    }

    private func isMessage(_ lhs: ChatMessage, newerThan rhs: ChatMessage) -> Bool {
        let lhsDate = lhs.sentAt ?? .distantPast
        let rhsDate = rhs.sentAt ?? .distantPast
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        if lhs.seq != rhs.seq { return lhs.seq > rhs.seq }
        return lhs.ID > rhs.ID
    }

    private func normalizedIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func combineAndSortInitialWindow(
        before: [ChatMessage],
        after: [ChatMessage]
    ) -> [ChatMessage] {
        var seen = Set<String>()
        let combined = (before + after).filter { seen.insert($0.ID).inserted }
        return combined.sorted { lhs, rhs in
            if lhs.seq != rhs.seq { return lhs.seq < rhs.seq }
            return lhs.ID < rhs.ID
        }
    }

    private func makeInitialWindow(
        messages: [ChatMessage],
        readBoundarySeq: Int64?,
        latestSeq: Int64
    ) -> ChatInitialWindow {
        let firstSeq = messages.first?.seq ?? 0
        let windowMaxSeq = messages.last?.seq ?? 0

        return ChatInitialWindow(
            messages: messages,
            readBoundarySeq: readBoundarySeq,
            latestSeq: latestSeq,
            hasMoreOlder: firstSeq > 1,
            hasMoreNewer: windowMaxSeq < latestSeq
        )
    }

    private func appendingFailedOutgoingMessages(
        to window: ChatInitialWindow,
        roomID: String
    ) async throws -> ChatInitialWindow {
        guard !roomID.isEmpty else { return window }
        let senderUID = LoginManager.shared.canonicalUserID
        let failed = try await messagePersistence
            .fetchFailedOutgoingMessages(inRoom: roomID, senderUID: senderUID)

        guard !failed.isEmpty else { return window }
        try? await messagePersistence.saveChatMessages(failed, accountID: accountID, session: cacheSession)

        let serverIDs = Set(window.messages.map(\.ID))
        let unresolvedFailed = failed.filter { !serverIDs.contains($0.ID) }
        let messages = window.messages + unresolvedFailed
        return ChatInitialWindow(
            messages: messages,
            readBoundarySeq: window.readBoundarySeq,
            latestSeq: window.latestSeq,
            hasMoreOlder: window.hasMoreOlder,
            hasMoreNewer: window.hasMoreNewer
        )
    }
}
