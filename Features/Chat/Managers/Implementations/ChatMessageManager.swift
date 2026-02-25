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
    private let grdbManager: GRDBManager
    
    init(
        messageRepository: FirebaseMessageRepositoryProtocol = FirebaseRepositoryProvider.shared.messageRepository,
        grdbManager: GRDBManager = .shared
    ) {
        self.messageRepository = messageRepository
        self.grdbManager = grdbManager
    }

    func loadLocalRecentMessages(roomID: String, limit: Int) async throws -> [ChatMessage] {
        try await Task(priority: .userInitiated) {
            try await grdbManager.fetchRecentMessages(inRoom: roomID, limit: limit)
        }.value
    }

    func fetchInitialServerMessages(room: ChatRoom, pageSize: Int) async throws -> [ChatMessage] {
        try await messageRepository.fetchMessagesPaged(for: room, pageSize: pageSize, reset: true)
    }

    func persistFetchedServerMessages(_ messages: [ChatMessage]) async throws {
        guard !messages.isEmpty else { return }
        try await grdbManager.saveChatMessages(messages)
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

        var localOlder = try await grdbManager.fetchOlderMessages(
            inRoom: roomID,
            before: anchor.ID,
            limit: normalizedBefore
        )
        var localNewer = try await grdbManager.fetchNewerMessages(
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
            try? await grdbManager.saveChatMessages(fetchedFromServer)
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
        let local = try await grdbManager.fetchOlderMessages(inRoom: roomID, before: messageID ?? "", limit: 100)
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
                try await grdbManager.saveChatMessages(server)
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
        try await grdbManager.saveChatMessages(server)
        
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
        try await grdbManager.updateMessagesIsDeleted(idsToUpdate, isDeleted: true, inRoom: roomID)
        try await grdbManager.updateReplyPreviewsIsDeleted(referencing: idsToUpdate, isDeleted: true, inRoom: roomID)
        
        return idsToUpdate
    }
    
    func deleteMessage(message: ChatMessage, room: ChatRoom) async throws {
        let messageID = message.ID
        let roomID = room.ID ?? ""
        
        // 1. GRDB 업데이트
        try await grdbManager.updateMessagesIsDeleted([messageID], isDeleted: true, inRoom: roomID)
        try grdbManager.deleteImageIndex(forMessageID: messageID, inRoom: roomID)
        
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
                group.addTask {
                    FirebaseImageStorageRepository.shared.deleteImageFromStorage(path: path)
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
                try await grdbManager.saveChatMessages([message])
                
                // LocalUser + RoomMember 업데이트
                do {
                    _ = try grdbManager.upsertLocalUser(
                        email: message.senderID,
                        nickname: message.senderNickname,
                        profileImagePath: message.senderAvatarPath
                    )
                    try grdbManager.addLocalUser(message.senderID, toRoom: message.roomID)
                } catch {
                    print("⚠️ LocalUser/RoomMember 업데이트 실패: \(error)")
                }
                
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
        if !message.isFailed, message.senderID == LoginManager.shared.getUserEmail {
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
                    try await self.grdbManager.updateMessagesIsDeleted([deletedMessageID], isDeleted: true, inRoom: roomID)
                    try await self.grdbManager.updateReplyPreviewsIsDeleted(referencing: [deletedMessageID], isDeleted: true, inRoom: roomID)
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
}
