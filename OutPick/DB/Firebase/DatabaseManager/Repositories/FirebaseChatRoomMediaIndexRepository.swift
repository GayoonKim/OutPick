//
//  FirebaseChatRoomMediaIndexRepository.swift
//  OutPick
//
//  Created by Codex on 3/7/26.
//

import Foundation
import FirebaseFirestore

final class FirebaseChatRoomMediaIndexRepository: FirebaseChatRoomMediaIndexRepositoryProtocol {
    private let db: Firestore

    init(db: Firestore) {
        self.db = db
    }

    func addMediaIndexWrites(for message: ChatMessage, in batch: WriteBatch) {
        let entries = ChatRoomMediaIndexEntry.entries(from: message)
        guard !entries.isEmpty else { return }

        for entry in entries {
            let ref = mediaIndexCollection(roomID: entry.roomID).document(entry.documentID)
            batch.setData(firestoreData(for: entry), forDocument: ref, merge: true)
        }
    }

    func markMediaIndexDeleted(roomID: String, messageID: String) async throws {
        guard !roomID.isEmpty, !messageID.isEmpty else { return }

        let snapshot = try await mediaIndexCollection(roomID: roomID)
            .whereField("messageID", isEqualTo: messageID)
            .getDocuments()

        guard !snapshot.documents.isEmpty else { return }

        let batch = db.batch()
        for document in snapshot.documents {
            batch.updateData(["isDeleted": true], forDocument: document.reference)
        }
        try await batch.commit()
    }

    func fetchLatestMedia(inRoom roomID: String, limit: Int) async throws -> [ChatRoomMediaIndexEntry] {
        guard !roomID.isEmpty, limit > 0 else { return [] }

        let snapshot = try await baseQuery(roomID: roomID)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap(decodeEntry(from:))
    }

    func fetchOlderMedia(
        inRoom roomID: String,
        before cursor: ChatRoomMediaIndexCursor,
        limit: Int
    ) async throws -> [ChatRoomMediaIndexEntry] {
        guard !roomID.isEmpty, limit > 0 else { return [] }

        let snapshot = try await baseQuery(roomID: roomID)
            .start(after: [Timestamp(date: cursor.sentAt), cursor.messageID, cursor.idx])
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap(decodeEntry(from:))
    }

    private func mediaIndexCollection(roomID: String) -> CollectionReference {
        db.collection("Rooms")
            .document(roomID)
            .collection("mediaIndex")
    }

    private func baseQuery(roomID: String) -> Query {
        mediaIndexCollection(roomID: roomID)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "sentAt", descending: true)
            .order(by: "messageID", descending: true)
            .order(by: "idx", descending: false)
    }

    private func firestoreData(for entry: ChatRoomMediaIndexEntry) -> [String: Any] {
        var data: [String: Any] = [
            "roomID": entry.roomID,
            "messageID": entry.messageID,
            "idx": entry.idx,
            "seq": entry.seq,
            "senderID": entry.senderID,
            "type": entry.type.rawValue,
            "isDeleted": entry.isDeleted,
            "sentAt": Timestamp(date: entry.sentAt)
        ]

        if let thumbKey = entry.thumbKey, !thumbKey.isEmpty {
            data["thumbKey"] = thumbKey
        }
        if let originalKey = entry.originalKey, !originalKey.isEmpty {
            data["originalKey"] = originalKey
        }
        if let thumbURL = entry.thumbURL, !thumbURL.isEmpty {
            data["thumbURL"] = thumbURL
        }
        if let originalURL = entry.originalURL, !originalURL.isEmpty {
            data["originalURL"] = originalURL
        }
        if let width = entry.width {
            data["width"] = width
        }
        if let height = entry.height {
            data["height"] = height
        }
        if let bytesOriginal = entry.bytesOriginal {
            data["bytesOriginal"] = bytesOriginal
        }
        if let duration = entry.duration {
            data["duration"] = duration
        }
        if let hash = entry.hash, !hash.isEmpty {
            data["hash"] = hash
        }

        return data
    }

    private func decodeEntry(from document: QueryDocumentSnapshot) -> ChatRoomMediaIndexEntry? {
        let data = document.data()
        let roomID = (data["roomID"] as? String) ?? document.reference.parent.parent?.documentID ?? ""
        let messageID = data["messageID"] as? String ?? ""
        let idx = intValue(from: data["idx"]) ?? 0

        guard !roomID.isEmpty, !messageID.isEmpty else { return nil }

        let seq = int64Value(from: data["seq"]) ?? 0

        let senderID = data["senderID"] as? String ?? ""
        let type = Attachment.AttachmentType(rawValue: data["type"] as? String ?? "image") ?? .image
        let sentAt = (data["sentAt"] as? Timestamp)?.dateValue() ?? Date.distantPast

        return ChatRoomMediaIndexEntry(
            roomID: roomID,
            messageID: messageID,
            idx: idx,
            seq: seq,
            senderID: senderID,
            type: type,
            thumbKey: data["thumbKey"] as? String,
            originalKey: data["originalKey"] as? String,
            thumbURL: data["thumbURL"] as? String,
            originalURL: data["originalURL"] as? String,
            width: intValue(from: data["width"]),
            height: intValue(from: data["height"]),
            bytesOriginal: intValue(from: data["bytesOriginal"]),
            duration: doubleValue(from: data["duration"]),
            hash: data["hash"] as? String,
            isDeleted: data["isDeleted"] as? Bool ?? false,
            sentAt: sentAt
        )
    }

    private func intValue(from value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        return nil
    }

    private func int64Value(from value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        return nil
    }

    private func doubleValue(from value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Float { return Double(value) }
        return nil
    }
}
