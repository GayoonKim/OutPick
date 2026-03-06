//
//  FirebaseMessageRepository.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import FirebaseFirestore

final class FirebaseMessageRepository: FirebaseMessageRepositoryProtocol {
    private let db: Firestore
    private let mediaIndexRepository: FirebaseChatRoomMediaIndexRepositoryProtocol
    private var lastFetchedMessageSnapshot: DocumentSnapshot?
    
    init(
        db: Firestore,
        paginationStateRepository: PaginationStateRepositoryProtocol? = nil,
        mediaIndexRepository: FirebaseChatRoomMediaIndexRepositoryProtocol? = nil
    ) {
        self.db = db
        self.mediaIndexRepository = mediaIndexRepository ?? FirebaseChatRoomMediaIndexRepository(db: db)
    }
    
    func saveMessage(_ message: ChatMessage, _ room: ChatRoom) async throws {
        do {
            guard let roomID = room.ID, !roomID.isEmpty else {
                throw FirebaseError.FailedToFetchRoom
            }
            let messageRef = db.collection("Rooms")
                .document(roomID)
                .collection("Messages")
                .document(message.ID)

            let batch = db.batch()
            batch.setData(message.toDict(), forDocument: messageRef)
            mediaIndexRepository.addMediaIndexWrites(for: message, in: batch)
            try await batch.commit()
            
            print("메시지 저장 성공 => \(message)")
        } catch {
            print("메시지 전송 및 저장 실패")
            throw error
        }
    }
    
    func listenToDeletedMessages(roomID: String,
                                 onDeleted: @escaping (String) -> Void) -> ListenerRegistration {
        return db.collection("Rooms")
            .document(roomID)
            .collection("Messages")
            .whereField("isDeleted", isEqualTo: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ listenToDeletedMessages 오류: \(error)")
                    return
                }
                guard let snapshot = snapshot else { return }
                
                for change in snapshot.documentChanges {
                    if change.type == .added || change.type == .modified {
                        let doc = change.document
                        let mid = (doc.get("ID") as? String) ?? doc.documentID
                        onDeleted(mid)
                        print("🗑 삭제 감지된 메시지: messageID=\(mid), docID=\(doc.documentID)")
                    }
                }
            }
    }
    
    func updateMessageIsDeleted(roomID: String, messageID: String) async throws {
        guard !roomID.isEmpty, !messageID.isEmpty else {
            throw FirebaseError.FailedToFetchRoom
        }
        do {
            let query = db.collection("Rooms")
                .document(roomID)
                .collection("Messages")
                .whereField("ID", isEqualTo: messageID)
                .limit(to: 10)
            let snapshot = try await query.getDocuments()
            guard snapshot.isEmpty == false else {
                print("⚠️ 메시지 문서를 찾을 수 없음 (roomID=\(roomID), messageID=\(messageID))")
                throw FirebaseError.FailedToFetchRoom
            }
            let batch = db.batch()
            for doc in snapshot.documents {
                batch.updateData(["isDeleted": true], forDocument: doc.reference)
                print("✅ 메시지 삭제 업데이트 성공: docID=\(doc.documentID), messageID=\(messageID)")
            }
            try await batch.commit()
            try await mediaIndexRepository.markMediaIndexDeleted(roomID: roomID, messageID: messageID)
        } catch {
            print("🔥 메시지 삭제 업데이트 실패: \(error)")
            throw error
        }
    }
    
    func fetchDeletionStates(roomID: String, messageIDs: [String]) async throws -> [String: Bool] {
        guard !roomID.isEmpty else { throw FirebaseError.FailedToFetchRoom }
        guard !messageIDs.isEmpty else { return [:] }
        
        var result: [String: Bool] = [:]
        let chunkSize = 10
        var start = 0
        while start < messageIDs.count {
            let end = min(start + chunkSize, messageIDs.count)
            let chunk = Array(messageIDs[start..<end])
            start = end
            
            let snap = try await db.collection("Rooms")
                .document(roomID)
                .collection("Messages")
                .whereField("ID", in: chunk)
                .getDocuments()
            
            for doc in snap.documents {
                let mid = (doc.get("ID") as? String) ?? doc.documentID
                let isDel = (doc.get("isDeleted") as? Bool) ?? false
                result[mid] = isDel
            }
        }
        return result
    }
    
    func fetchMessagesPaged(for room: ChatRoom, pageSize: Int = 50, reset: Bool = false) async throws -> [ChatMessage] {
        guard let roomID = room.ID else {
            print("❌ fetchMessagesPaged: room.ID is nil")
            return []
        }
        
        let collection = db
            .collection("Rooms")
            .document(roomID)
            .collection("Messages")
        
        if reset { lastFetchedMessageSnapshot = nil }
        
        var query: Query = collection
            .order(by: "seq", descending: false)
            .limit(to: pageSize)
        
        if let lastSnapshot = lastFetchedMessageSnapshot {
            query = query.start(afterDocument: lastSnapshot)
        }
        
        let snapshot = try await query.getDocuments()
        lastFetchedMessageSnapshot = snapshot.documents.last
        
        let messages: [ChatMessage] = snapshot.documents.compactMap { doc in
            var dict = doc.data()
            if dict["ID"] == nil { dict["ID"] = doc.documentID }
            if let msg = ChatMessage.from(dict) { return msg }
            do { return try doc.data(as: ChatMessage.self) } catch {
                print("⚠️ 디코딩 실패(관대파서/코더 모두 실패): \(error), docID: \(doc.documentID), data=\(dict)")
                return nil
            }
        }
        return messages
    }
    
    func fetchOlderMessages(for room: ChatRoom, before messageID: String, limit: Int = 100) async throws -> [ChatMessage] {
        guard let roomID = room.ID else { return [] }
        
        let anchorDoc = try await db
            .collection("Rooms").document(roomID)
            .collection("Messages").document(messageID)
            .getDocument()
        guard anchorDoc.exists, let anchorData = anchorDoc.data() else { return [] }
        
        if let anySeq = anchorData["seq"] {
            let anchorSeq: Int64
            if let num = anySeq as? NSNumber { anchorSeq = num.int64Value }
            else if let i = anySeq as? Int { anchorSeq = Int64(i) }
            else if let l = anySeq as? Int64 { anchorSeq = l }
            else { anchorSeq = 0 }
            
            let snapshot = try await db
                .collection("Rooms").document(roomID)
                .collection("Messages")
                .whereField("seq", isLessThan: anchorSeq)
                .order(by: "seq", descending: true)
                .limit(to: limit)
                .getDocuments()
            
            let messages: [ChatMessage] = snapshot.documents.compactMap { doc in
                var dict = doc.data()
                if dict["ID"] == nil { dict["ID"] = doc.documentID }
                if let msg = ChatMessage.from(dict) { return msg }
                do { return try doc.data(as: ChatMessage.self) } catch {
                    print("⚠️ 디코딩 실패: \(error), docID: \(doc.documentID), data=\(dict)")
                    return nil
                }
            }
            return messages.reversed()
        }
        
        let anchorSentAt = (anchorData["sentAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
        let snapshot = try await db
            .collection("Rooms").document(roomID)
            .collection("Messages")
            .whereField("sentAt", isLessThan: Timestamp(date: anchorSentAt))
            .order(by: "sentAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let messages: [ChatMessage] = snapshot.documents.compactMap { doc in
            var dict = doc.data()
            if dict["ID"] == nil { dict["ID"] = doc.documentID }
            if let msg = ChatMessage.from(dict) { return msg }
            do { return try doc.data(as: ChatMessage.self) } catch {
                print("⚠️ 디코딩 실패: \(error), docID: \(doc.documentID), data=\(dict)")
                return nil
            }
        }
        return messages.reversed()
    }
    
    func fetchMessagesAfter(room: ChatRoom, after messageID: String, limit: Int = 100) async throws -> [ChatMessage] {
        guard let roomID = room.ID else { return [] }
        
        let anchorDoc = try await db
            .collection("Rooms").document(roomID)
            .collection("Messages").document(messageID)
            .getDocument()
        guard anchorDoc.exists, let anchorData = anchorDoc.data() else { return [] }
        
        if let anySeq = anchorData["seq"] {
            let anchorSeq: Int64
            if let num = anySeq as? NSNumber { anchorSeq = num.int64Value }
            else if let i = anySeq as? Int { anchorSeq = Int64(i) }
            else if let l = anySeq as? Int64 { anchorSeq = l }
            else { anchorSeq = 0 }
            
            let snapshot = try await db
                .collection("Rooms").document(roomID)
                .collection("Messages")
                .whereField("seq", isGreaterThan: anchorSeq)
                .order(by: "seq", descending: false)
                .limit(to: limit)
                .getDocuments()
            
            let messages: [ChatMessage] = snapshot.documents.compactMap { doc in
                var dict = doc.data()
                if dict["ID"] == nil { dict["ID"] = doc.documentID }
                if let msg = ChatMessage.from(dict) { return msg }
                do { return try doc.data(as: ChatMessage.self) } catch {
                    print("⚠️ 디코딩 실패: \(error), docID: \(doc.documentID), data=\(dict)")
                    return nil
                }
            }
            return messages
        }
        
        let anchorSentAt = (anchorData["sentAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
        let snapshot = try await db
            .collection("Rooms").document(roomID)
            .collection("Messages")
            .whereField("sentAt", isGreaterThan: Timestamp(date: anchorSentAt))
            .order(by: "sentAt", descending: false)
            .limit(to: limit)
            .getDocuments()
        
        let messages: [ChatMessage] = snapshot.documents.compactMap { doc in
            var dict = doc.data()
            if dict["ID"] == nil { dict["ID"] = doc.documentID }
            if let msg = ChatMessage.from(dict) { return msg }
            do { return try doc.data(as: ChatMessage.self) } catch {
                print("⚠️ 디코딩 실패: \(error), docID: \(doc.documentID), data=\(dict)")
                return nil
            }
        }
        return messages
    }
    
    func fetchPreviewMessages(roomID: String, limit: Int) async -> [ChatMessage] {
        let messagesRef = db.collection("Rooms").document(roomID).collection("Messages")
        
        func decode(_ snap: QuerySnapshot) -> [ChatMessage] {
            let arr: [ChatMessage] = snap.documents.compactMap { doc in
                var dict = doc.data()
                if dict["ID"] == nil { dict["ID"] = doc.documentID }
                if let msg = ChatMessage.from(dict) { return msg }
                do { return try doc.data(as: ChatMessage.self) }
                catch {
                    print("⚠️ preview decode failed: \(error), docID: \(doc.documentID)")
                    return nil
                }
            }
            return arr
        }
        
        do {
            let snap = try await messagesRef
                .order(by: "seq", descending: true)
                .limit(to: limit)
                .getDocuments()
            let arr = decode(snap)
            if !arr.isEmpty { return arr.reversed() }
        } catch {
            // fallback
        }
        
        do {
            let snap = try await messagesRef
                .order(by: "sentAt", descending: true)
                .limit(to: limit)
                .getDocuments()
            let arr = decode(snap)
            return arr.reversed()
        } catch {
            print("⚠️ fetchPreviewMessages fallback failed (roomID=\(roomID)): \(error)")
            return []
        }
    }

    func searchMessagesInRoom(roomID: String, keyword: String) async throws -> ChatMessageServerSearchResponse {
        guard !roomID.isEmpty else {
            return ChatMessageServerSearchResponse(totalCount: 0, hits: [])
        }
        guard let tokenQuery = ChatMessageSearchIndex.queryToken(for: keyword) else {
            return ChatMessageServerSearchResponse(totalCount: 0, hits: [])
        }

        let snapshot = try await db.collection("Rooms")
            .document(roomID)
            .collection("Messages")
            .whereField(tokenQuery.field, arrayContains: tokenQuery.token)
            .getDocuments()

        let candidates: [ChatMessage] = snapshot.documents.compactMap { doc in
            var dict = doc.data()
            if dict["ID"] == nil { dict["ID"] = doc.documentID }
            if let msg = ChatMessage.from(dict) { return msg }
            do { return try doc.data(as: ChatMessage.self) } catch {
                print("⚠️ 검색 디코딩 실패: \(error), docID: \(doc.documentID)")
                return nil
            }
        }

        let filtered = candidates
            .filter { ChatMessageSearchIndex.contains($0.msg, keyword: keyword) }
            .sorted { lhs, rhs in
                if lhs.seq != rhs.seq { return lhs.seq < rhs.seq }
                return lhs.ID < rhs.ID
            }

        let hits = filtered.map { message in
            ChatMessageSearchHit(message: message, snippet: message.msg)
        }
        return ChatMessageServerSearchResponse(totalCount: hits.count, hits: hits)
    }
    
}
