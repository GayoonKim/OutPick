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

    func fetchMessageDeletionRevision(roomID: String) async throws -> Int64 {
        guard !roomID.isEmpty else { throw FirebaseError.FailedToFetchRoom }
        let snapshot = try await db.collection("Rooms").document(roomID).getDocument()
        guard snapshot.exists else { throw FirebaseError.FailedToFetchRoom }
        return Self.int64(snapshot.get("messageDeletionRevision")) ?? 0
    }

    func fetchDeletionDeltas(
        roomID: String,
        afterRevision: Int64,
        limit: Int
    ) async throws -> [ChatDeletionDelta] {
        guard !roomID.isEmpty else { throw FirebaseError.FailedToFetchRoom }
        guard limit > 0 else { return [] }
        let snapshot = try await db.collection("Rooms")
            .document(roomID)
            .collection("Messages")
            .whereField("deletionRevision", isGreaterThan: afterRevision)
            .order(by: "deletionRevision", descending: false)
            .limit(to: min(limit, 100))
            .getDocuments()
        return snapshot.documents.compactMap { Self.deletionDelta(document: $0, roomID: roomID) }
    }

    func fetchDeletionDeltas(roomID: String, messageIDs: [String]) async throws -> [ChatDeletionDelta] {
        guard !roomID.isEmpty else { throw FirebaseError.FailedToFetchRoom }
        guard !messageIDs.isEmpty else { return [] }
        var result: [ChatDeletionDelta] = []
        for start in stride(from: 0, to: messageIDs.count, by: 10) {
            let chunk = Array(messageIDs[start..<min(start + 10, messageIDs.count)])
            let snapshot = try await db.collection("Rooms")
                .document(roomID)
                .collection("Messages")
                .whereField("ID", in: chunk)
                .getDocuments()
            result.append(contentsOf: snapshot.documents.compactMap {
                Self.deletionDelta(document: $0, roomID: roomID)
            })
        }
        return result.sorted { $0.revision < $1.revision }
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

    private static func deletionDelta(document: QueryDocumentSnapshot, roomID: String) -> ChatDeletionDelta? {
        let data = document.data()
        guard data["isDeleted"] as? Bool == true,
              let revision = int64(data["deletionRevision"]), revision > 0 else { return nil }
        let messageID = (data["ID"] as? String) ?? document.documentID
        guard !messageID.isEmpty else { return nil }
        return ChatDeletionDelta(
            messageID: messageID,
            roomID: roomID,
            seq: int64(data["seq"]) ?? 0,
            revision: revision,
            deletedAt: (data["deletedAt"] as? Timestamp)?.dateValue(),
            anonymizesSender: (data["senderAnonymized"] as? Bool) ??
                ((data["senderUID"] as? String)?.isEmpty != false)
        )
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Int64 { return value }
        if let value = value as? Double { return Int64(value) }
        return nil
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
