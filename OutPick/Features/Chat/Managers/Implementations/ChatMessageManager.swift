//
//  ChatMessageManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import Combine

final class ChatMessageManager: ChatMessageManaging {
    private let messageRepository: FirebaseMessageRepositoryProtocol
    private let imageStorageRepository: FirebaseImageStorageRepositoryProtocol
    private let messagePersistence: ChatMessagePersisting
    private let profileCache: ChatProfileCachePersisting
    private let profileDisplayCacheLimit = 20
    
    init(
        messageRepository: FirebaseMessageRepositoryProtocol = FirebaseRepositoryProvider.shared.messageRepository,
        imageStorageRepository: FirebaseImageStorageRepositoryProtocol = FirebaseRepositoryProvider.shared.imageStorageRepository,
        messagePersistence: ChatMessagePersisting,
        profileCache: ChatProfileCachePersisting
    ) {
        self.messageRepository = messageRepository
        self.imageStorageRepository = imageStorageRepository
        self.messagePersistence = messagePersistence
        self.profileCache = profileCache
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
            let messages = try await messageRepository.fetchLatestMessages(
                for: room,
                limit: policy.latestTailSize
            )
            return try await appendingFailedOutgoingMessages(
                to: makeInitialWindow(
                messages: messages,
                readBoundarySeq: nil,
                latestSeq: latestSeq
                ),
                roomID: room.ID ?? ""
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
                roomID: room.ID ?? ""
            )
        }
    }

    func persistFetchedServerMessages(_ messages: [ChatMessage]) async throws {
        guard !messages.isEmpty else { return }
        try await messagePersistence.saveChatMessages(messages)
        persistSenderDisplayCache(for: messages)
    }

    func loadMessagesAroundAnchor(
        room: ChatRoom,
        anchor: ChatMessage,
        beforeLimit: Int,
        afterLimit: Int
    ) async throws -> [ChatMessage] {
        let roomID = room.ID ?? ""
        guard !roomID.isEmpty else { return [anchor] }

        let normalizedBefore = max(0, beforeLimit)
        let normalizedAfter = max(0, afterLimit)

        var localOlder = try await messagePersistence.fetchOlderMessages(
            inRoom: roomID,
            before: anchor.ID,
            limit: normalizedBefore
        )
        var localNewer = try await messagePersistence.fetchNewerMessages(
            inRoom: roomID,
            after: anchor.ID,
            limit: normalizedAfter
        )

        var fetchedFromServer: [ChatMessage] = []

        let olderDeficit = max(0, normalizedBefore - localOlder.count)
        if olderDeficit > 0 {
            let serverOlder = try await messageRepository.fetchOlderMessages(
                for: room,
                before: anchor.ID,
                limit: olderDeficit
            )
            if !serverOlder.isEmpty {
                fetchedFromServer.append(contentsOf: serverOlder)
                // older는 ASC 반환. 로컬 older 앞쪽으로 합쳐준다.
                let localIDs = Set(localOlder.map(\.ID))
                let missingOlder = serverOlder.filter { !localIDs.contains($0.ID) }
                localOlder = (missingOlder + localOlder)
            }
        }

        let newerDeficit = max(0, normalizedAfter - localNewer.count)
        if newerDeficit > 0 {
            let serverNewer = try await messageRepository.fetchMessagesAfter(
                room: room,
                after: anchor.ID,
                limit: newerDeficit
            )
            if !serverNewer.isEmpty {
                fetchedFromServer.append(contentsOf: serverNewer)
                let localIDs = Set(localNewer.map(\.ID))
                let missingNewer = serverNewer.filter { !localIDs.contains($0.ID) }
                localNewer.append(contentsOf: missingNewer)
            }
        }

        if !fetchedFromServer.isEmpty {
            do {
                try await messagePersistence.saveChatMessages(fetchedFromServer)
                persistSenderDisplayCache(for: fetchedFromServer)
            } catch {
                print("⚠️ fetched messages local persistence failed:", error)
            }
        }

        var combined: [ChatMessage] = []
        combined.reserveCapacity(localOlder.count + 1 + localNewer.count)
        combined.append(contentsOf: localOlder)
        combined.append(anchor)
        combined.append(contentsOf: localNewer)

        // ID 기준 중복 제거 + seq 오름차순 정렬
        var seen = Set<String>()
        let deduped = combined.filter { seen.insert($0.ID).inserted }
        return deduped.sorted { lhs, rhs in
            if lhs.seq != rhs.seq { return lhs.seq < rhs.seq }
            return lhs.ID < rhs.ID
        }
    }
    
    func loadOlderMessages(room: ChatRoom, before messageID: String?) async throws -> [ChatMessage] {
        let roomID = room.ID ?? ""
        
        // 1. GRDB에서 먼저 최대 100개
        let local = try await messagePersistence.fetchOlderMessages(inRoom: roomID, before: messageID ?? "", limit: 100)
        var loadedMessages = local
        
        // 2. 부족분은 서버에서 채우기
        if local.count < 100 {
            let needed = 100 - local.count
            let server = try await messageRepository.fetchOlderMessages(
                for: room,
                before: messageID ?? "",
                limit: needed
            )
            
            if !server.isEmpty {
                try await messagePersistence.saveChatMessages(server)
                persistSenderDisplayCache(for: server)
                loadedMessages.append(contentsOf: server)
            }
        }
        
        return loadedMessages
    }
    
    func loadNewerMessages(room: ChatRoom, after messageID: String?) async throws -> [ChatMessage] {
        let server = try await messageRepository.fetchMessagesAfter(
            room: room,
            after: messageID ?? "",
            limit: 100
        )
        
        guard !server.isEmpty else { return [] }
        try await messagePersistence.saveChatMessages(server)
        persistSenderDisplayCache(for: server)
        
        return server
    }
    
    func syncDeletedStates(localMessages: [ChatMessage], room: ChatRoom) async throws -> [String] {
        let localIDs = localMessages.map { $0.ID }
        let localDeletionStates = Dictionary(uniqueKeysWithValues: localMessages.map { ($0.ID, $0.isDeleted) })
        
        let serverMap = try await messageRepository.fetchDeletionStates(roomID: room.ID ?? "", messageIDs: localIDs)
        
        // 서버가 true인데 로컬은 false인 ID만 업데이트 대상
        let idsToUpdate = localIDs.filter { (serverMap[$0] ?? false) && ((localDeletionStates[$0] ?? false) == false) }
        guard !idsToUpdate.isEmpty else { return [] }
        
        let roomID = room.ID ?? ""
        try await applyLocalDeletion(idsToUpdate, inRoom: roomID)
        
        return idsToUpdate
    }
    
    func deleteMessage(message: ChatMessage, room: ChatRoom) async throws {
        let messageID = message.ID
        let roomID = room.ID ?? ""
        
        // 1. GRDB 업데이트
        try await applyLocalDeletion([messageID], inRoom: roomID)
        
        // 2. Firestore 업데이트
        try await messageRepository.updateMessageIsDeleted(roomID: roomID, messageID: messageID)
        
        // 3. Storage 파일 삭제
        let rawPaths = message.attachments.flatMap { [$0.pathThumb, $0.pathOriginal] }
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        
        guard !rawPaths.isEmpty else { return }
        
        var seen = Set<String>()
        let uniquePaths = rawPaths.filter { seen.insert($0).inserted }
        
        await withTaskGroup(of: Void.self) { group in
            for path in uniquePaths {
                group.addTask { [imageStorageRepository] in
                    imageStorageRepository.deleteImageFromStorage(path: path)
                }
            }
        }
    }
    
    func handleIncomingMessage(_ message: ChatMessage, room: ChatRoom) async throws {
        // 메시지 저장 (재시도 로직 포함)
        let maxRetries = 3
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                try await messagePersistence.saveChatMessages([message])
                persistSenderDisplayCache(for: [message])
                
                lastError = nil
                break
            } catch {
                lastError = error
                print("⚠️ GRDB saveChatMessages 실패 (시도 \(attempt)/\(maxRetries)): \(error)")
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: UInt64(200_000_000) * UInt64(attempt))
                }
            }
        }
        
        if let err = lastError {
            print("❌ GRDB saveChatMessages 최종 실패: \(err)")
        }
        
        // 내가 보낸 정상 메시지면 Firebase 기록
        if !message.isFailed, message.senderUID == LoginManager.shared.canonicalUserID {
            Task(priority: .utility) {
                do {
                    try await messageRepository.saveMessage(message, room)
                } catch {
                    print("⚠️ Firebase saveMessage 실패(비차단): \(error)")
                }
            }
        }
    }
    
    func setupDeletionListener(roomID: String, onDeleted: @escaping (String) -> Void) -> AnyCancellable {
        let listener = messageRepository.listenToDeletedMessages(roomID: roomID) { deletedMessageID in
            Task.detached(priority: .medium) {
                do {
                    try await self.applyLocalDeletion([deletedMessageID], inRoom: roomID)
                } catch {
                    print("❌ GRDB deletion persistence failed:", error)
                }
                
                await MainActor.run {
                    onDeleted(deletedMessageID)
                }
            }
        }
        
        return AnyCancellable {
            listener.remove()
        }
    }
    
    func saveMessage(_ message: ChatMessage, room: ChatRoom) async throws {
        try await messageRepository.saveMessage(message, room)
    }

    private func applyLocalDeletion(_ messageIDs: [String], inRoom roomID: String) async throws {
        guard !messageIDs.isEmpty, !roomID.isEmpty else { return }

        try await messagePersistence.applyDeletion(messageIDs: messageIDs, inRoom: roomID)
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
        try? await messagePersistence.saveChatMessages(failed)

        let failedIDs = Set(failed.map(\.ID))
        let messages = window.messages.filter { !failedIDs.contains($0.ID) } + failed
        return ChatInitialWindow(
            messages: messages,
            readBoundarySeq: window.readBoundarySeq,
            latestSeq: window.latestSeq,
            hasMoreOlder: window.hasMoreOlder,
            hasMoreNewer: window.hasMoreNewer
        )
    }
}
