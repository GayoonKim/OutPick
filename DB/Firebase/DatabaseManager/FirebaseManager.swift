//
//  FirestoreManager.swift
//  OutPick
//
//  Created by 김가윤 on 10/10/24.
//

import Foundation
import FirebaseFirestore
import FirebaseStorage
import Alamofire
import Kingfisher
import Combine

/// FirebaseManager는 Facade 패턴으로 각 Repository의 기능을 통합 제공합니다.
class FirebaseManager {
    
    private init() {
        let db = Firestore.firestore()
        self.userProfileRepository = UserProfileRepository(db: db)
        self.chatRoomRepository = ChatRoomRepository(db: db)
        self.messageRepository = MessageRepository(db: db)
        self.announcementRepository = AnnouncementRepository(db: db)
        self.paginationManager = PaginationManager()
    }
    
    // FirestoreManager의 싱글톤 인스턴스
    static let shared = FirebaseManager()
    
    // Firestore 인스턴스
    let db = Firestore.firestore()
    // Storage 인스턴스
    let storage = Storage.storage()
    
    let joinedRoomStore = JoinedRoomsStore()
    
    // MARK: - Repository 인스턴스
    private let userProfileRepository: UserProfileRepositoryProtocol
    private let chatRoomRepository: ChatRoomRepositoryProtocol
    private let messageRepository: MessageRepositoryProtocol
    private let announcementRepository: AnnouncementRepositoryProtocol
    private let paginationManager: PaginationManagerProtocol
    
    // MARK: - Convenience Properties (기존 API 호환성 유지)
    var topRoomsWithPreviews: [(ChatRoom, [ChatMessage])] {
        return chatRoomRepository.topRoomsWithPreviews
    }
    
    var roomChangePublisher: AnyPublisher<ChatRoom, Never> {
        return chatRoomRepository.roomChangePublisher
    }

    // MARK: - 프로필 관련 기능 (UserProfileRepository 위임)
    func listenToUserProfile(email: String) {
        userProfileRepository.listenToUserProfile(email: email)
    }
    
    func userProfilePublisher(email: String) -> AnyPublisher<UserProfile, Error> {
        return userProfileRepository.userProfilePublisher(email: email)
    }
    
    func stopListenUserProfile(email: String) {
        userProfileRepository.stopListenUserProfile(email: email)
    }
    
    func saveUserProfileToFirestore(email: String) async throws {
        try await userProfileRepository.saveUserProfileToFirestore(email: email)
    }
    
    func fetchUserProfileFromFirestore(email: String) async throws -> UserProfile {
        return try await userProfileRepository.fetchUserProfileFromFirestore(email: email)
    }
    
    func fetchUserProfiles(emails: [String]) async throws -> [UserProfile] {
        return try await userProfileRepository.fetchUserProfiles(emails: emails)
    }
    
    func checkDuplicate(strToCompare: String, fieldToCompare: String, collectionName: String) async throws -> Bool {
        return try await userProfileRepository.checkDuplicate(strToCompare: strToCompare, fieldToCompare: fieldToCompare, collectionName: collectionName)
    }
    
    func updateLastReadSeq(roomID: String, userID: String, lastReadSeq: Int64) async throws {
        try await userProfileRepository.updateLastReadSeq(roomID: roomID, userID: userID, lastReadSeq: lastReadSeq)
    }
    
    func fetchLastReadSeq(for roomID: String) async throws -> Int64 {
        return try await userProfileRepository.fetchLastReadSeq(for: roomID)
    }
    
    // MARK: - 채팅방 관련 기능 (ChatRoomRepository 위임)
    func applyLocalRoomUpdate(_ updatedRoom: ChatRoom) {
        chatRoomRepository.applyLocalRoomUpdate(updatedRoom)
    }
    
    func fetchLatestSeq(for roomID: String) async throws -> Int64 {
        return try await chatRoomRepository.fetchLatestSeq(for: roomID)
    }
    
    @MainActor
    func fetchTopRoomsPage(after lastSnapshot: DocumentSnapshot? = nil, limit: Int = 30) async throws {
        try await chatRoomRepository.fetchTopRoomsPage(after: lastSnapshot, limit: limit)
    }
    
    @MainActor
    func updateRoomLastMessage(roomID: String, date: Date? = nil, msg: String) async {
        await chatRoomRepository.updateRoomLastMessage(roomID: roomID, date: date, msg: msg)
    }
    
    func editRoom(room: ChatRoom,
                  pickedImage: UIImage?,
                  imageData: MediaManager.ImagePair?,
                  isRemoved: Bool,
                  newName: String,
                  newDesc: String) async throws -> ChatRoom {
        return try await chatRoomRepository.editRoom(room: room, pickedImage: pickedImage, imageData: imageData, isRemoved: isRemoved, newName: newName, newDesc: newDesc)
    }
    
    func getRoomDoc(room: ChatRoom) async throws -> DocumentSnapshot? {
        return try await chatRoomRepository.getRoomDoc(room: room)
    }
    
    func saveRoomInfoToFirestore(room: ChatRoom) async throws {
        try await chatRoomRepository.saveRoomInfoToFirestore(room: room)
    }
    
    func fetchRoomsWithIDs(byIDs ids: [String]) async throws -> [ChatRoom] {
        return try await chatRoomRepository.fetchRoomsWithIDs(byIDs: ids)
    }
    
    func searchRooms(keyword: String, limit: Int = 30, reset: Bool = true) async throws -> [ChatRoom] {
        return try await chatRoomRepository.searchRooms(keyword: keyword, limit: limit, reset: reset)
    }
    
    func loadMoreSearchRooms(limit: Int = 30) async throws -> [ChatRoom] {
        return try await chatRoomRepository.loadMoreSearchRooms(limit: limit)
    }
    
    @MainActor
    func startListenRoomDoc(roomID: String) {
        chatRoomRepository.startListenRoomDoc(roomID: roomID)
    }
    
    @MainActor
    func startListenRoomDocs(roomIDs: [String]) {
        chatRoomRepository.startListenRoomDocs(roomIDs: roomIDs)
    }
    
    @MainActor
    func stopListenAllRoomDocs() {
        chatRoomRepository.stopListenAllRoomDocs()
    }
    
    @MainActor
    func updateRoomInfo(room: ChatRoom, newImagePath: String, roomName: String, roomDescription: String) async throws {
        try await chatRoomRepository.updateRoomInfo(room: room, newImagePath: newImagePath, roomName: roomName, roomDescription: roomDescription)
    }
    
    func checkRoomName(roomName: String, completion: @escaping (Bool, Error?) -> Void) {
        chatRoomRepository.checkRoomName(roomName: roomName, completion: completion)
    }
    
    func add_room_participant(room: ChatRoom) async throws {
        try await chatRoomRepository.add_room_participant(room: room)
    }
    
    func add_room_participant_returningRoom(roomID: String) async throws -> ChatRoom {
        return try await chatRoomRepository.add_room_participant_returningRoom(roomID: roomID)
    }
    
    func remove_participant(room: ChatRoom) {
        chatRoomRepository.remove_participant(room: room)
    }
    

    // MARK: - 공지 관련 기능 (AnnouncementRepository 위임)
    @MainActor
    func setActiveAnnouncement(roomID: String,
                               messageID: String?,
                               payload: AnnouncementPayload?) async throws {
        try await announcementRepository.setActiveAnnouncement(roomID: roomID, messageID: messageID, payload: payload)
    }
    
    @MainActor
    func setActiveAnnouncement(room: ChatRoom,
                               messageID: String?,
                               payload: AnnouncementPayload?) async throws {
        try await announcementRepository.setActiveAnnouncement(room: room, messageID: messageID, payload: payload)
    }
    
    @MainActor
    func setActiveAnnouncement(room: ChatRoom,
                               text: String,
                               authorID: String) async throws {
        try await announcementRepository.setActiveAnnouncement(room: room, text: text, authorID: authorID)
    }
    
    @MainActor
    func clearActiveAnnouncement(roomID: String) async throws {
        try await announcementRepository.clearActiveAnnouncement(roomID: roomID)
    }
    
    @MainActor
    func clearActiveAnnouncement(room: ChatRoom) async throws {
        try await announcementRepository.clearActiveAnnouncement(room: room)
    }

    // MARK: - 메시지 관련 기능 (MessageRepository 위임)
    func saveMessage(_ message: ChatMessage, _ room: ChatRoom) async throws {
        try await messageRepository.saveMessage(message, room)
    }
    
    func listenToDeletedMessages(roomID: String,
                                 onDeleted: @escaping (String) -> Void) -> ListenerRegistration {
        return messageRepository.listenToDeletedMessages(roomID: roomID, onDeleted: onDeleted)
    }
    
    func updateMessageIsDeleted(roomID: String, messageID: String) async throws {
        try await messageRepository.updateMessageIsDeleted(roomID: roomID, messageID: messageID)
    }
    
    func fetchDeletionStates(roomID: String, messageIDs: [String]) async throws -> [String: Bool] {
        return try await messageRepository.fetchDeletionStates(roomID: roomID, messageIDs: messageIDs)
    }
    
    func fetchMessagesPaged(for room: ChatRoom, pageSize: Int = 50, reset: Bool = false) async throws -> [ChatMessage] {
        return try await messageRepository.fetchMessagesPaged(for: room, pageSize: pageSize, reset: reset)
    }
    
    func fetchOlderMessages(for room: ChatRoom, before messageID: String, limit: Int = 100) async throws -> [ChatMessage] {
        return try await messageRepository.fetchOlderMessages(for: room, before: messageID, limit: limit)
    }
    
    func fetchMessagesAfter(room: ChatRoom, after messageID: String, limit: Int = 100) async throws -> [ChatMessage] {
        return try await messageRepository.fetchMessagesAfter(room: room, after: messageID, limit: limit)
    }
}

extension UIImage {
    func resized(withMaxWidth maxWidth: CGFloat) -> UIImage {
        let aspectRatio = size.height / size.width
        let newSize = CGSize(width: min(maxWidth, size.width), height: min(maxWidth, size.width) * aspectRatio)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

extension Notification.Name {
    static let chatRoomsUpdated = Notification.Name("chatRoomsUpdated")
}
