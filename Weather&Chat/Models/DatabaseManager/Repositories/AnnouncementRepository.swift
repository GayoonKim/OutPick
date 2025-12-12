//
//  AnnouncementRepository.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import FirebaseFirestore

final class AnnouncementRepository: AnnouncementRepositoryProtocol {
    private let db: Firestore
    
    init(db: Firestore) {
        self.db = db
    }
    
    @MainActor
    func setActiveAnnouncement(roomID: String,
                               messageID: String?,
                               payload: AnnouncementPayload?) async throws {
        guard !roomID.isEmpty else { throw FirebaseError.FailedToFetchRoom }
        var update: [String: Any] = [:]
        
        if let messageID = messageID {
            update["activeAnnouncementID"] = messageID
        } else {
            update["activeAnnouncementID"] = FieldValue.delete()
        }
        
        if let payload = payload {
            update["activeAnnouncement"] = payload.toDictionary()
            update["announcementUpdatedAt"] = Timestamp(date: payload.createdAt)
        } else {
            update["activeAnnouncement"] = FieldValue.delete()
            update["announcementUpdatedAt"] = FieldValue.serverTimestamp()
        }
        
        let ref = db.collection("Rooms").document(roomID)
        try await ref.updateData(update)
    }
    
    @MainActor
    func setActiveAnnouncement(room: ChatRoom,
                               messageID: String?,
                               payload: AnnouncementPayload?) async throws {
        guard let roomID = room.ID else { throw FirebaseError.FailedToFetchRoom }
        try await setActiveAnnouncement(roomID: roomID, messageID: messageID, payload: payload)
    }
    
    @MainActor
    func setActiveAnnouncement(room: ChatRoom,
                               text: String,
                               authorID: String) async throws {
        let payload = AnnouncementPayload(text: text, authorID: authorID, createdAt: Date())
        try await setActiveAnnouncement(room: room, messageID: nil, payload: payload)
    }
    
    @MainActor
    func clearActiveAnnouncement(roomID: String) async throws {
        try await setActiveAnnouncement(roomID: roomID, messageID: nil, payload: nil)
    }
    
    @MainActor
    func clearActiveAnnouncement(room: ChatRoom) async throws {
        guard let roomID = room.ID else { throw FirebaseError.FailedToFetchRoom }
        try await clearActiveAnnouncement(roomID: roomID)
    }
}

