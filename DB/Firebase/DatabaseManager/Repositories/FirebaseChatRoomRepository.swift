//
//  FirebaseChatRoomRepository.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import Combine
import FirebaseFirestore
import UIKit

final class FirebaseChatRoomRepository: FirebaseChatRoomRepositoryProtocol {
    private let db: Firestore
    
    // 채팅방 목록 캐시
    private(set) var topRoomsWithPreviews: [(ChatRoom, [ChatMessage])] = []
    private var previewByRoomID: [String: [ChatMessage]] = [:]
    
    // 방 문서 리스너
    private var roomDocListeners: [String: ListenerRegistration] = [:]
    private let roomChangeSubject = PassthroughSubject<ChatRoom, Never>()
    var roomChangePublisher: AnyPublisher<ChatRoom, Never> {
        return roomChangeSubject.eraseToAnyPublisher()
    }

    // 참여중 방 head(요약) 실시간 리스너
    private var joinedRoomsSummaryListener: ListenerRegistration?
    private let joinedRoomsSummarySubject = CurrentValueSubject<[ChatRoom], Never>([])
    private var joinedRoomsSummaryConfig: (email: String, limit: Int)?
    var joinedRoomsSummaryPublisher: AnyPublisher<[ChatRoom], Never> {
        joinedRoomsSummarySubject.eraseToAnyPublisher()
    }
    
    // 페이지네이션 상태
    private var lastFetchedRoomSnapshot: DocumentSnapshot?
    private var lastSearchSnapshot: DocumentSnapshot?
    private var currentSearchKeyword: String = ""
    
    // 작업 관리
    private var addRoomParticipantTask: Task<Void, Never>?
    private var removeParticipantTask: Task<Void, Never>?
    
    init(db: Firestore) {
        self.db = db
    }
    
    deinit {
        addRoomParticipantTask?.cancel()
        removeParticipantTask?.cancel()
        joinedRoomsSummaryListener?.remove()
        // deinit에서는 MainActor 메서드를 직접 호출할 수 없으므로 직접 정리
        cleanupListeners()
    }
    
    func applyLocalRoomUpdate(_ updatedRoom: ChatRoom) {
        guard let rid = updatedRoom.ID, !rid.isEmpty else { return }
        if let idx = topRoomsWithPreviews.firstIndex(where: { $0.0.ID == rid }) {
            let previews = topRoomsWithPreviews[idx].1
            topRoomsWithPreviews[idx] = (updatedRoom, previews)
        }
    }

    @MainActor
    func applyRealtimeSummaryPatch(roomID: String, message: String, sentAt: Date, seq: Int64?, senderID: String?) {
        guard !roomID.isEmpty else { return }
        let preview = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preview.isEmpty else { return }

        var rooms = joinedRoomsSummarySubject.value
        guard let idx = rooms.firstIndex(where: { $0.ID == roomID }) else { return }

        var room = rooms[idx]
        room.lastMessage = preview
        room.lastMessageAt = sentAt
        if let senderID, !senderID.isEmpty {
            room.lastMessageSenderID = senderID
        }
        if let seq, seq > room.seq {
            room.seq = seq
        }
        rooms[idx] = room
        rooms.sort { (lhs, rhs) in
            (lhs.lastMessageAt ?? lhs.createdAt) > (rhs.lastMessageAt ?? rhs.createdAt)
        }
        joinedRoomsSummarySubject.send(rooms)
    }
    
    @MainActor
    func fetchTopRoomsPage(after lastSnapshot: DocumentSnapshot? = nil, limit: Int = 30) async throws {
        var query: Query = db.collection("Rooms").order(by: "lastMessageAt", descending: true).limit(to: limit)
        
        if let lastSnapshot {
            query = query.start(afterDocument: lastSnapshot)
        }
        
        let snapshot = try await query.getDocuments()
        
        let rooms: [ChatRoom] = snapshot.documents.compactMap { doc in
            do {
                return try self.createRoom(from: doc)
            } catch {
                print("⚠️ Room decode failed: \(error), id=\(doc.documentID)")
                return nil
            }
        }
        
        // 각 방의 최근 메시지 3개 동시 로드
        let previewsByRoomID: [String: [ChatMessage]] = await withTaskGroup(of: (String, [ChatMessage]).self) { group in
            for r in rooms {
                guard let rid = r.ID, !rid.isEmpty else { continue }
                group.addTask { [weak self] in
                    guard let self = self else { return ("", []) }
                    let msgs = await self.fetchPreviewMessages(roomID: rid, limit: 3)
                    return (rid, msgs)
                }
            }
            
            var acc: [String: [ChatMessage]] = [:]
            for await (rid, msgs) in group {
                guard !rid.isEmpty else { continue }
                acc[rid] = msgs
            }
            return acc
        }
        
        self.previewByRoomID = previewsByRoomID
        self.topRoomsWithPreviews = rooms.map { room in
            let rid = room.ID ?? ""
            let previews = previewsByRoomID[rid] ?? []
            return (room, previews)
        }
        
        self.lastFetchedRoomSnapshot = snapshot.documents.last
    }
    
    private func fetchPreviewMessages(roomID: String, limit: Int) async -> [ChatMessage] {
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
        
        // 1) seq 기반 시도
        do {
            let snap = try await messagesRef
                .order(by: "seq", descending: true)
                .limit(to: limit)
                .getDocuments()
            let arr = decode(snap)
            if !arr.isEmpty { return arr.reversed() }
        } catch {
            // 계속 폴백 시도
        }
        
        // 2) sentAt 기반 폴백
        do {
            let snap = try await messagesRef
                .order(by: "sentAt", descending: true)
                .limit(to: limit)
                .getDocuments()
            let arr = decode(snap)
            return arr.reversed()
        } catch {
            print("⚠️ _fetchPreviewMessages fallback failed (roomID=\(roomID)): \(error)")
            return []
        }
    }
    
    @MainActor
    func updateRoomLastMessage(roomID: String, date: Date? = nil, msg: String, senderID: String? = nil) async {
        guard !roomID.isEmpty else {
            print("❌ updateRoomLastMessageAt: roomID is empty")
            return
        }
        
        do {
            let ref = db.collection("Rooms").document(roomID)
            var updateData: [String: Any] = [:]
            
            updateData["lastMessage"] = msg
            if let senderID, !senderID.isEmpty {
                updateData["lastMessageSenderID"] = senderID
            }
            if let date = date {
                updateData["lastMessageAt"] = Timestamp(date: date)
            } else {
                updateData["lastMessageAt"] = FieldValue.serverTimestamp()
            }
            updateData["updatedAt"] = FieldValue.serverTimestamp()
            
            try await ref.updateData(updateData)
            print("✅ lastMessageAt 업데이트 성공 → \(roomID)")
        } catch {
            print("🔥 lastMessageAt 업데이트 실패: \(error)")
        }
    }
    
    func editRoom(room: ChatRoom,
                  pickedImage: UIImage?,
                  imageData: DefaultMediaProcessingService.ImagePair?,
                  isRemoved: Bool,
                  newName: String,
                  newDesc: String) async throws -> ChatRoom {
        
        let roomRef = db.collection("Rooms").document(room.ID ?? "")
        let oldThumb = room.thumbPath
        let oldOriginal = room.originalPath
        
        var uploadedThumb: String? = nil
        var uploadedOriginal: String? = nil
        
        if isRemoved {
            try await roomRef.updateData([
                "thumbPath": FieldValue.delete(),
                "originalPath": FieldValue.delete(),
                "roomName": newName,
                "roomDescription": newDesc,
                "updatedAt": FieldValue.serverTimestamp()
            ])
            Task.detached {
                if let t = oldThumb { FirebaseImageStorageRepository.shared.deleteImageFromStorage(path: t) }
                if let o = oldOriginal { FirebaseImageStorageRepository.shared.deleteImageFromStorage(path: o) }
            }
        } else if let pair = imageData {
            let (newThumb, newOriginal) = try await FirebaseImageStorageRepository.shared.uploadAndSave(
                sha: pair.fileBaseName,
                uid: room.ID ?? "",
                type: .roomImage,
                thumbData: pair.thumbData,
                originalFileURL: pair.originalFileURL
            )
            uploadedThumb = newThumb
            uploadedOriginal = newOriginal
        } else {
            try await roomRef.updateData([
                "roomName": newName,
                "roomDescription": newDesc,
                "updatedAt": FieldValue.serverTimestamp()
            ])
        }
        
        var updated = room
        updated.roomName = newName
        updated.roomDescription = newDesc
        if isRemoved {
            updated.thumbPath = nil
            updated.originalPath = nil
        } else if let ut = uploadedThumb, let uo = uploadedOriginal {
            updated.thumbPath = ut
            updated.originalPath = uo
        }
        
        return updated
    }
    
    func getRoomDoc(room: ChatRoom) async throws -> DocumentSnapshot? {
        let roomRef = db.collection("Rooms").document(room.ID ?? "")
        let room_snapshot = try await roomRef.getDocument()
        
        guard room_snapshot.exists else {
            print("방 문서 불러오기 실패")
            return nil
        }
        
        return room_snapshot
    }
    
    func saveRoomInfoToFirestore(room: ChatRoom) async throws {
        guard let roomID = room.ID, !roomID.isEmpty else {
            print("❌ saveRoomInfoToFirestore: room.ID is nil/empty")
            throw FirebaseError.FailedToFetchRoom
        }
        
        let roomRef = db.collection("Rooms").document(roomID)
        
        do {
            _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                var roomData = room.toDictionary()
                roomData["updatedAt"] = FieldValue.serverTimestamp()
                transaction.setData(roomData, forDocument: roomRef)
                return nil
            })
            
            try await addRoomParticipant(room: room)
            
            SocketIOManager.shared.createRoom(roomID)
            SocketIOManager.shared.joinRoom(roomID)
            
            print("✅ saveRoomInfoToFirestore: Firestore 저장 및 Socket.IO create/join 완료 (roomID=\(roomID))")
        } catch {
            print("🔥 saveRoomInfoToFirestore 실패: \(error)")
            throw error
        }
    }
    
    func fetchRoomsWithIDs(byIDs ids: [String]) async throws -> [ChatRoom] {
        guard !ids.isEmpty else { return [] }
        var result: [ChatRoom] = []
        var start = 0
        
        while start < ids.count {
            let end = min(start + 10, ids.count)
            let chunk = Array(ids[start..<end])
            start = end
            
            let snap = try await db
                .collection("Rooms")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            
            let rooms = snap.documents.compactMap { doc -> ChatRoom? in
                try? doc.data(as: ChatRoom.self)
            }
            result.append(contentsOf: rooms)
        }
        
        return result
    }
    
    func searchRooms(keyword: String, limit: Int = 30, reset: Bool = true) async throws -> [ChatRoom] {
        guard !keyword.isEmpty else { return [] }
        
        if reset {
            lastSearchSnapshot = nil
            currentSearchKeyword = keyword
        }
        
        var query: Query = db.collection("Rooms")
            .order(by: "lastMessageAt", descending: true)
            .limit(to: limit)
        
        query = query
            .whereField("roomName", isGreaterThanOrEqualTo: keyword)
            .whereField("roomName", isLessThanOrEqualTo: keyword + "\u{f8ff}")
        
        if let last = lastSearchSnapshot {
            query = query.start(afterDocument: last)
        }
        
        let snap = try await query.getDocuments()
        lastSearchSnapshot = snap.documents.last
        
        let rooms = snap.documents.compactMap { doc -> ChatRoom? in
            try? doc.data(as: ChatRoom.self)
        }
        return rooms
    }
    
    func loadMoreSearchRooms(limit: Int = 30) async throws -> [ChatRoom] {
        guard !currentSearchKeyword.isEmpty else { return [] }
        return try await searchRooms(keyword: currentSearchKeyword, limit: limit, reset: false)
    }

    @MainActor
    func startListenJoinedRoomsSummary(userEmail: String, limit: Int = 50) {
        let normalizedEmail = userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty else { return }
        let boundedLimit = max(1, limit)

        if let config = joinedRoomsSummaryConfig,
           config.email == normalizedEmail,
           config.limit == boundedLimit,
           joinedRoomsSummaryListener != nil {
            return
        }

        joinedRoomsSummaryListener?.remove()
        joinedRoomsSummaryListener = nil
        joinedRoomsSummaryConfig = (normalizedEmail, boundedLimit)

        let query = db.collection("Rooms")
            .whereField("participantIDs", arrayContains: normalizedEmail)
            .order(by: "lastMessageAt", descending: true)
            .limit(to: boundedLimit)

        joinedRoomsSummaryListener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                print("❌ JoinedRooms summary listener error:", error)
                return
            }
            guard let snapshot else { return }

            let rooms: [ChatRoom] = snapshot.documents.compactMap { doc in
                do {
                    return try self.createRoom(from: doc)
                } catch {
                    print("⚠️ JoinedRooms summary decode failed:", error, "docID:", doc.documentID)
                    return nil
                }
            }
            self.joinedRoomsSummarySubject.send(rooms)
        }
    }

    @MainActor
    func stopListenJoinedRoomsSummary() {
        joinedRoomsSummaryListener?.remove()
        joinedRoomsSummaryListener = nil
        joinedRoomsSummaryConfig = nil
    }

    func fetchJoinedRoomsPage(
        userEmail: String,
        after lastSnapshot: DocumentSnapshot? = nil,
        limit: Int = 50
    ) async throws -> (rooms: [ChatRoom], lastSnapshot: DocumentSnapshot?) {
        let normalizedEmail = userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty else { return ([], nil) }

        var query: Query = db.collection("Rooms")
            .whereField("participantIDs", arrayContains: normalizedEmail)
            .order(by: "lastMessageAt", descending: true)
            .limit(to: max(1, limit))

        if let lastSnapshot {
            query = query.start(afterDocument: lastSnapshot)
        }

        let snapshot = try await query.getDocuments()
        let rooms: [ChatRoom] = snapshot.documents.compactMap { doc in
            do {
                return try self.createRoom(from: doc)
            } catch {
                print("⚠️ JoinedRooms page decode failed:", error, "docID:", doc.documentID)
                return nil
            }
        }
        return (rooms, snapshot.documents.last)
    }

    func fetchJoinedRoomsUpdatedSince(
        userEmail: String,
        since: Date,
        limit: Int = 200
    ) async throws -> [ChatRoom] {
        let normalizedEmail = userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty else { return [] }

        let snapshot = try await db.collection("Rooms")
            .whereField("participantIDs", arrayContains: normalizedEmail)
            .whereField("updatedAt", isGreaterThan: Timestamp(date: since))
            .order(by: "updatedAt", descending: true)
            .limit(to: max(1, limit))
            .getDocuments()

        let rooms: [ChatRoom] = snapshot.documents.compactMap { doc in
            do {
                return try self.createRoom(from: doc)
            } catch {
                print("⚠️ JoinedRooms delta decode failed:", error, "docID:", doc.documentID)
                return nil
            }
        }
        return rooms
    }
    
    @MainActor
    func startListenRoomDoc(roomID: String) {
        if roomDocListeners[roomID] != nil { return }
        
        let ref = db.collection("Rooms").document(roomID)
        let l = ref.addSnapshotListener { [weak self] snap, err in
            guard let self = self else { return }
            if let err = err {
                print("❌ Room listener error:", err)
                return
            }
            guard let snap = snap, snap.exists else { return }
            do {
                let room = try self.createRoom(from: snap)
                Task { @MainActor in
                    if let id = room.ID, !id.isEmpty {
                        self.roomChangeSubject.send(room)
                    }
                }
            } catch {
                print("❌ Room decode error:", error)
            }
        }
        roomDocListeners[roomID] = l
    }
    
    @MainActor
    func stopListenRoomDoc() {
        cleanupListeners()
    }
    
    // MainActor가 아닌 컨텍스트에서도 호출 가능한 리스너 정리 메서드
    private func cleanupListeners() {
        for (_, listener) in roomDocListeners {
            listener.remove()
        }
        roomDocListeners.removeAll()
    }
    
    @MainActor
    func updateRoomInfo(room: ChatRoom, newImagePath: String, roomName: String, roomDescription: String) async throws {
        guard let roomDoc = try await getRoomDoc(room: room) else {
            throw FirebaseError.FailedToFetchRoom
        }
        
        var updateData: [String: Any] = [:]
        updateData["roomImagePath"] = newImagePath
        updateData["roomName"] = roomName
        updateData["roomDescription"] = roomDescription
        updateData["updatedAt"] = FieldValue.serverTimestamp()
        
        try await roomDoc.reference.updateData(updateData)
    }
    
    func checkRoomName(roomName: String, completion: @escaping (Bool, Error?) -> Void) {
        db.collection("Rooms").whereField("roomName", isEqualTo: roomName).getDocuments { snapshot, error in
            if let error = error {
                completion(false, error)
                return
            }
            
            if let snapshot = snapshot, snapshot.isEmpty {
                completion(false, nil)
            } else {
                completion(true, nil)
            }
        }
    }

    func checkRoomNameDuplicate(roomName: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            checkRoomName(roomName: roomName) { isDuplicate, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: isDuplicate)
            }
        }
    }
    
    func addRoomParticipant(room: ChatRoom) async throws {
        addRoomParticipantTask?.cancel()
        addRoomParticipantTask = Task {
            do {
                guard let roomDoc = try await getRoomDoc(room: room) else { return }
                let userKey = LoginManager.shared.getRoomStateUserKey
                guard !userKey.isEmpty else {
                    print("⚠️ addRoomParticipant: userKey 없음")
                    return
                }
                let userRef = db.collection("users").document(userKey)
                
                let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                    transaction.updateData(["joinedRooms": FieldValue.arrayUnion([room.ID ?? ""])], forDocument: userRef)
                    transaction.updateData([
                        "participantIDs": FieldValue.arrayUnion([LoginManager.shared.getUserEmail]),
                        "updatedAt": FieldValue.serverTimestamp()
                    ], forDocument: roomDoc.reference)
                    return nil
                })
                
                print(#function, "참여자 업데이트 성공")
                addRoomParticipantTask = nil
            } catch {
                print(#function, "방 참여자 업데이트 트랜젝션 실패: \(error)")
            }
        }
    }
    
    func addRoomParticipantReturningRoom(roomID: String) async throws -> ChatRoom {
        guard !roomID.isEmpty else {
            throw FirebaseError.FailedToFetchRoom
        }
        let email = LoginManager.shared.getUserEmail
        let userKey = LoginManager.shared.getRoomStateUserKey
        guard !userKey.isEmpty else {
            throw FirebaseError.FailedToFetchRoom
        }
        let userRef = db.collection("users").document(userKey)
        let roomRef = db.collection("Rooms").document(roomID)
        
        _ = try await db.runTransaction { (transaction, errorPointer) -> Any? in
            transaction.updateData(["joinedRooms": FieldValue.arrayUnion([roomID])], forDocument: userRef)
            transaction.updateData([
                "participantIDs": FieldValue.arrayUnion([email]),
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: roomRef)
            return nil
        }
        
        let snap = try await roomRef.getDocument(source: .server)
        guard snap.exists else {
            throw FirebaseError.FailedToFetchRoom
        }
        do {
            let updated = try self.createRoom(from: snap)
            return updated
        } catch {
            print("❌ addRoomParticipantReturningRoom decode error:", error)
            throw FirebaseError.FailedToParseRoomData
        }
    }
    
    func removeParticipant(room: ChatRoom) {
        removeParticipantTask?.cancel()
        removeParticipantTask = Task {
            do {
                guard let roomID = room.ID, !roomID.isEmpty else {
                    print("⚠️ removeParticipant: roomID 없음")
                    return
                }
                let email = LoginManager.shared.getUserEmail
                let userKey = LoginManager.shared.getRoomStateUserKey
                guard !userKey.isEmpty else {
                    print("⚠️ removeParticipant: userKey 없음")
                    return
                }
                let userRef = db.collection("users").document(userKey)
                let roomRef = db.collection("Rooms").document(roomID)
                let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                    transaction.updateData(["joinedRooms": FieldValue.arrayRemove([roomID])], forDocument: userRef)
                    transaction.updateData([
                        "participantIDs": FieldValue.arrayRemove([email]),
                        "updatedAt": FieldValue.serverTimestamp()
                    ], forDocument: roomRef)
                    return nil
                })
                
                if let thumbPath = room.thumbPath {
                    KingFisherCacheManager.shared.removeImage(forKey: thumbPath)
                }
                if let originalpath = room.originalPath {
                    KingFisherCacheManager.shared.removeImage(forKey: originalpath)
                }
                
                print("참여중인 방 강제 삭제 성공")
                removeParticipantTask = nil
            } catch {
                print("방 참여자 강제 삭제 트랜젝션 실패: \(error)")
            }
        }
    }
    
    func fetchLatestSeq(for roomID: String) async throws -> Int64 {
        let roomRef = db.collection("Rooms").document(roomID)
        let roomSnap = try await roomRef.getDocument()
        let roomData = roomSnap.data()
        if let agg = Self.toInt64(roomData?["seq"]), agg > 0 {
            return agg
        }
        if let agg = Self.toInt64(roomData?["lastMessageSeq"]), agg > 0 {
            return agg
        }

        let upperMessages = try await roomRef.collection("Messages")
            .order(by: "seq", descending: true)
            .limit(to: 1)
            .getDocuments()
        if let latest = Self.toInt64(upperMessages.documents.first?.data()["seq"]), latest > 0 {
            return latest
        }

        let lowerMessages = try await roomRef.collection("messages")
            .order(by: "seq", descending: true)
            .limit(to: 1)
            .getDocuments()
        return Self.toInt64(lowerMessages.documents.first?.data()["seq"]) ?? 0
    }
    
    // MARK: - Private Helpers
    private func createRoom(from document: DocumentSnapshot) throws -> ChatRoom {
        do {
            return try document.data(as: ChatRoom.self)
        } catch {
            print("채팅방 디코딩 실패: \(error), docID: \(document.documentID)")
            throw FirebaseError.FailedToParseRoomData
        }
    }

    private static func toInt64(_ raw: Any?) -> Int64? {
        if let number = raw as? NSNumber { return number.int64Value }
        if let value = raw as? Int64 { return value }
        if let value = raw as? Int { return Int64(value) }
        if let value = raw as? UInt64 {
            return value > UInt64(Int64.max) ? Int64.max : Int64(value)
        }
        if let value = raw as? String, let parsed = Int64(value) { return parsed }
        if let value = raw as? Double { return Int64(value) }
        return nil
    }
}
