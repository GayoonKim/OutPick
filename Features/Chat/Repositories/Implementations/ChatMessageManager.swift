//
//  ChatMessageManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import Combine
import FirebaseFirestore

final class ChatMessageManager: ChatMessageManagerProtocol {
    private let firebaseManager: FirebaseManager
    private let grdbManager: GRDBManager
    private let socketManager: SocketIOManager
    
    init(
        firebaseManager: FirebaseManager = .shared,
        grdbManager: GRDBManager = .shared,
        socketManager: SocketIOManager = .shared
    ) {
        self.firebaseManager = firebaseManager
        self.grdbManager = grdbManager
        self.socketManager = socketManager
    }
    
    func loadInitialMessages(room: ChatRoom, isParticipant: Bool) async throws -> (local: [ChatMessage], server: [ChatMessage]) {
        let roomID = room.ID ?? ""
        
        if !isParticipant {
            // 미참여자: 서버에서만 미리보기
            let previewMessages = try await firebaseManager.fetchMessagesPaged(for: room, pageSize: 100, reset: true)
            return ([], previewMessages)
        }
        
        // 참여자: 로컬 + 서버
        let localMessages = try await Task(priority: .userInitiated) {
            try await grdbManager.fetchRecentMessages(inRoom: roomID, limit: 200)
        }.value
        
        let serverMessages = try await firebaseManager.fetchMessagesPaged(for: room, pageSize: 300, reset: true)
        try await grdbManager.saveChatMessages(serverMessages)
        
        // 발신자 정보 동기화
        let combined = localMessages + serverMessages
        Task.detached(priority: .utility) { [roomID, combined] in
            var seenSenders = Set<String>()
            for msg in combined {
                let email = msg.senderID
                guard !email.isEmpty, seenSenders.insert(email).inserted else { continue }
                do {
                    _ = try self.grdbManager.upsertLocalUser(
                        email: email,
                        nickname: msg.senderNickname,
                        profileImagePath: msg.senderAvatarPath
                    )
                    try self.grdbManager.addLocalUser(email, toRoom: roomID)
                } catch {
                    print("⚠️ Initial LocalUser upsert/add 실패 (\(email)):", error)
                }
            }
        }
        
        return (localMessages, serverMessages)
    }
    
    func loadOlderMessages(room: ChatRoom, before messageID: String?) async throws -> [ChatMessage] {
        let roomID = room.ID ?? ""
        
        // 1. GRDB에서 먼저 최대 100개
        let local = try await grdbManager.fetchOlderMessages(inRoom: roomID, before: messageID ?? "", limit: 100)
        var loadedMessages = local
        
        // 2. 부족분은 서버에서 채우기
        if local.count < 100 {
            let needed = 100 - local.count
            let server = try await firebaseManager.fetchOlderMessages(
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
        let server = try await firebaseManager.fetchMessagesAfter(
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
        
        let serverMap = try await firebaseManager.fetchDeletionStates(roomID: room.ID ?? "", messageIDs: localIDs)
        
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
        try await firebaseManager.updateMessageIsDeleted(roomID: roomID, messageID: messageID)
        
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
                    FirebaseStorageManager.shared.deleteImageFromStorage(path: path)
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
                    try grdbManager.upsertLocalUser(
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
                    try await firebaseManager.saveMessage(message, room)
                } catch {
                    print("⚠️ Firebase saveMessage 실패(비차단): \(error)")
                }
            }
        }
    }
    
    func setupDeletionListener(roomID: String, onDeleted: @escaping (String) -> Void) -> AnyCancellable {
        let listener = firebaseManager.listenToDeletedMessages(roomID: roomID) { deletedMessageID in
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
        try await firebaseManager.saveMessage(message, room)
    }
}

