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
    private var lastFetchedMessageSnapshot: DocumentSnapshot?
    
    init(db: Firestore) {
        self.db = db
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
        let roomID = room.id
        guard !roomID.isEmpty else {
            print("❌ fetchMessagesPaged: room.id is empty")
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
        return decodeMessages(from: snapshot)
    }

    func fetchLatestMessages(for room: ChatRoom, limit: Int) async throws -> [ChatMessage] {
        let roomID = room.id

        let snapshot = try await db
            .collection("Rooms").document(roomID)
            .collection("Messages")
            .order(by: "seq", descending: true)
            .limit(to: limit)
            .getDocuments()

        return decodeMessages(from: snapshot).reversed()
    }

    func fetchMessagesAfterSeq(room: ChatRoom, afterSeq: Int64, limit: Int) async throws -> [ChatMessage] {
        let roomID = room.id
        guard limit > 0 else { return [] }

        let snapshot = try await db
            .collection("Rooms").document(roomID)
            .collection("Messages")
            .whereField("seq", isGreaterThan: afterSeq)
            .order(by: "seq", descending: false)
            .limit(to: limit)
            .getDocuments()

        return decodeMessages(from: snapshot)
    }

    func fetchMessagesBeforeSeq(room: ChatRoom, beforeSeq: Int64, limit: Int) async throws -> [ChatMessage] {
        let roomID = room.id
        guard limit > 0 else { return [] }

        let snapshot = try await db
            .collection("Rooms").document(roomID)
            .collection("Messages")
            .whereField("seq", isLessThan: beforeSeq)
            .order(by: "seq", descending: true)
            .limit(to: limit)
            .getDocuments()

        return decodeMessages(from: snapshot).reversed()
    }
    
    func fetchOlderMessages(for room: ChatRoom, before messageID: String, limit: Int = 100) async throws -> [ChatMessage] {
        let roomID = room.id
        
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
            
            return decodeMessages(from: snapshot).reversed()
        }
        
        let anchorSentAt = (anchorData["sentAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
        let snapshot = try await db
            .collection("Rooms").document(roomID)
            .collection("Messages")
            .whereField("sentAt", isLessThan: Timestamp(date: anchorSentAt))
            .order(by: "sentAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        return decodeMessages(from: snapshot).reversed()
    }
    
    func fetchMessagesAfter(room: ChatRoom, after messageID: String, limit: Int = 100) async throws -> [ChatMessage] {
        let roomID = room.id
        
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
            
            return decodeMessages(from: snapshot)
        }
        
        let anchorSentAt = (anchorData["sentAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
        let snapshot = try await db
            .collection("Rooms").document(roomID)
            .collection("Messages")
            .whereField("sentAt", isGreaterThan: Timestamp(date: anchorSentAt))
            .order(by: "sentAt", descending: false)
            .limit(to: limit)
            .getDocuments()
        
        return decodeMessages(from: snapshot)
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

    private func decodeMessages(from snapshot: QuerySnapshot) -> [ChatMessage] {
        snapshot.documents.compactMap { doc in
            var dict = doc.data()
            if dict["ID"] == nil { dict["ID"] = doc.documentID }
            if let msg = ChatMessage.from(dict) { return msg }
            do {
                return try doc.data(as: ChatMessage.self)
            } catch {
                print("⚠️ 디코딩 실패: \(error), docID: \(doc.documentID), data=\(dict)")
                return nil
            }
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
