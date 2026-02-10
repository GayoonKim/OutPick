//
//  ChatRoomRepository.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import Combine
import FirebaseFirestore
import UIKit

final class ChatRoomRepository: ChatRoomRepositoryProtocol {
    private let db: Firestore
    
    // 채팅방 목록 캐시
    private(set) var topRoomsWithPreviews: [(ChatRoom, [ChatMessage])] = []
    private var previewByRoomID: [String: [ChatMessage]] = [:]
    private var lastRoomIDsListened: Set<String> = []
    
    // 방 문서 리스너
    private var roomDocListeners: [String: ListenerRegistration] = [:]
    private var batchedRoomDocListeners: [String: ListenerRegistration] = [:]
    private let roomChangeSubject = PassthroughSubject<ChatRoom, Never>()
    var roomChangePublisher: AnyPublisher<ChatRoom, Never> {
        return roomChangeSubject.eraseToAnyPublisher()
    }
    
    // 페이지네이션 상태
    private var lastFetchedRoomSnapshot: DocumentSnapshot?
    private var lastSearchSnapshot: DocumentSnapshot?
    private var currentSearchKeyword: String = ""
    
    // 작업 관리
    private var add_room_participant_task: Task<Void, Never>?
    private var remove_participant_task: Task<Void, Never>?
    
    init(db: Firestore) {
        self.db = db
    }
    
    deinit {
        add_room_participant_task?.cancel()
        remove_participant_task?.cancel()
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
    func updateRoomLastMessage(roomID: String, date: Date? = nil, msg: String) async {
        guard !roomID.isEmpty else {
            print("❌ updateRoomLastMessageAt: roomID is empty")
            return
        }
        
        do {
            let ref = db.collection("Rooms").document(roomID)
            var updateData: [String: Any] = [:]
            
            updateData["lastMessage"] = msg
            if let date = date {
                updateData["lastMessageAt"] = Timestamp(date: date)
            } else {
                updateData["lastMessageAt"] = FieldValue.serverTimestamp()
            }
            
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
                "roomDescription": newDesc
            ])
            Task.detached {
                if let t = oldThumb { FirebaseImageStorageManager.shared.deleteImageFromStorage(path: t) }
                if let o = oldOriginal { FirebaseImageStorageManager.shared.deleteImageFromStorage(path: o) }
            }
        } else if let pair = imageData {
            let (newThumb, newOriginal) = try await FirebaseImageStorageManager.shared.uploadAndSave(
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
                "roomDescription": newDesc
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
                transaction.setData(room.toDictionary(), forDocument: roomRef)
                return nil
            })
            
            try await add_room_participant(room: room)
            
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
    func startListenRoomDoc(roomID: String) {
        if lastRoomIDsListened.contains(roomID) {
            print(#function, "skip per-doc listener (managed by batched):", roomID)
            return
        }
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
    func startListenRoomDocs(roomIDs: [String]) {
        let ids = Array(Set(roomIDs)).filter { !$0.isEmpty }
        let newSet = Set(ids)
        guard !newSet.isEmpty else {
            stopListenAllRoomDocs()
            return
        }
        
        if newSet == lastRoomIDsListened { return }
        lastRoomIDsListened = newSet
        
        for (_, l) in batchedRoomDocListeners { l.remove() }
        batchedRoomDocListeners.removeAll()
        for (_, l) in roomDocListeners { l.remove() }
        roomDocListeners.removeAll()
        
        let chunkSize = 10
        var index = 0
        while index < ids.count {
            let end = min(index + chunkSize, ids.count)
            let chunk = Array(ids[index..<end])
            index = end
            
            let key = chunk.sorted().joined(separator: ",")
            
            let q = db.collection("Rooms")
                .whereField(FieldPath.documentID(), in: chunk)
            
            let l = q.addSnapshotListener { [weak self] snap, err in
                guard let self = self else { return }
                if let err = err {
                    print("❌ Batched room docs listener error:", err)
                    return
                }
                guard let snap = snap else { return }
                
                Task { @MainActor in
                    for change in snap.documentChanges {
                        do {
                            let room = try self.createRoom(from: change.document)
                            if let id = room.ID, !id.isEmpty {
                                self.roomChangeSubject.send(room)
                            }
                        } catch {
                            print("⚠️ Batched decode failed:", error, "docID:", change.document.documentID)
                        }
                    }
                }
            }
            
            batchedRoomDocListeners[key] = l
            print(#function, "Added listener for chunk:", l)
        }
    }
    
    @MainActor
    func stopListenAllRoomDocs() {
        cleanupListeners()
    }
    
    // MainActor가 아닌 컨텍스트에서도 호출 가능한 리스너 정리 메서드
    private func cleanupListeners() {
        for (_, listener) in roomDocListeners {
            listener.remove()
        }
        roomDocListeners.removeAll()
        
        for (_, listener) in batchedRoomDocListeners {
            listener.remove()
        }
        batchedRoomDocListeners.removeAll()
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
    
    func add_room_participant(room: ChatRoom) async throws {
        add_room_participant_task?.cancel()
        add_room_participant_task = Task {
            do {
                guard let room_doc = try await getRoomDoc(room: room) else { return }
                let userRef = db.collection("Users").document(LoginManager.shared.getUserEmail)
                
                let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                    transaction.updateData(["joinedRooms": FieldValue.arrayUnion([room.ID ?? ""])], forDocument: userRef)
                    transaction.updateData(["participantIDs": FieldValue.arrayUnion([LoginManager.shared.getUserEmail])], forDocument: room_doc.reference)
                    return nil
                })
                
                print(#function, "참여자 업데이트 성공")
                add_room_participant_task = nil
            } catch {
                print(#function, "방 참여자 업데이트 트랜젝션 실패: \(error)")
            }
        }
    }
    
    func add_room_participant_returningRoom(roomID: String) async throws -> ChatRoom {
        guard !roomID.isEmpty else {
            throw FirebaseError.FailedToFetchRoom
        }
        let email = LoginManager.shared.getUserEmail
        let userRef = db.collection("Users").document(email)
        let roomRef = db.collection("Rooms").document(roomID)
        
        _ = try await db.runTransaction { (transaction, errorPointer) -> Any? in
            transaction.updateData(["joinedRooms": FieldValue.arrayUnion([roomID])], forDocument: userRef)
            transaction.updateData(["participantIDs": FieldValue.arrayUnion([email])], forDocument: roomRef)
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
            print("❌ add_room_participant_returningRoom decode error:", error)
            throw FirebaseError.FailedToParseRoomData
        }
    }
    
    func remove_participant(room: ChatRoom) {
        remove_participant_task?.cancel()
        remove_participant_task = Task {
            do {
                let userRef = db.collection("Users").document(LoginManager.shared.getUserEmail)
                let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                    transaction.updateData(["joinedRooms": FieldValue.arrayRemove([room.roomName])], forDocument: userRef)
                    return nil
                })
                
                if let thumbPath = room.thumbPath {
                    KingFisherCacheManager.shared.removeImage(forKey: thumbPath)
                }
                if let originalpath = room.originalPath {
                    KingFisherCacheManager.shared.removeImage(forKey: originalpath)
                }
                
                print("참여중인 방 강제 삭제 성공")
                remove_participant_task = nil
            } catch {
                print("방 참여자 강제 삭제 트랜젝션 실패: \(error)")
            }
        }
    }
    
    func fetchLatestSeq(for roomID: String) async throws -> Int64 {
        let roomRef = db.collection("Rooms").document(roomID)
        let roomSnap = try await roomRef.getDocument()
        if let agg = roomSnap.data()?["lastMessageSeq"] as? Int64 {
            return agg
        }
        let messagesRef = roomRef.collection("messages")
        let querySnap = try await messagesRef
            .order(by: "seq", descending: true)
            .limit(to: 1)
            .getDocuments()
        let latest = querySnap.documents.first?.data()["seq"] as? Int64 ?? 0
        return latest
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
}
