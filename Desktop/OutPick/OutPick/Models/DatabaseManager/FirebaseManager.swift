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

class FirebaseManager {
    
    private init() {}
    
    // FirestoreManager의 싱글톤 인스턴스
    static let shared = FirebaseManager()
    
    // Firestore 인스턴스
    let db = Firestore.firestore()
    
    // Storage 인스턴스
    let storage = Storage.storage()
    
    // 채팅방 목록
    @Published private(set) var chatRooms: [ChatRoom] = []
    private var roomsListener: ListenerRegistration?
    private var monthlyRoomListeners: [String: ListenerRegistration] = [:]
    
    private var listenToRoomsTask: Task<Void, Never>? = nil
    private var fetchProfileTask: Task<Void, Never>? = nil
    private var saveUserProfileTask: Task<Void, Never>? = nil
    private var add_room_participant_task: Task<Void, Never>? = nil
    private var remove_participant_task: Task<Void, Never>? = nil
    private var saveChatMessageTask: Task<Void, Never>? = nil
    
    deinit {
        listenToRoomsTask?.cancel()
        fetchProfileTask?.cancel()
        saveUserProfileTask?.cancel()
        add_room_participant_task?.cancel()
        remove_participant_task?.cancel()
        saveChatMessageTask?.cancel()
    }
    
    // 채팅방 읽기 전용 접근자 제공
    var currentChatRooms: [ChatRoom] {
        return chatRooms
    }

    private let roomChangeSubject = PassthroughSubject<ChatRoom, Never>()
    var roomChangePublisher: AnyPublisher<ChatRoom, Never> {
        return roomChangeSubject.eraseToAnyPublisher()
    }
    
    private var lastFetchedSnapshot: DocumentSnapshot?
    
    // Hot rooms with previews
    @Published var hotRoomsWithPreviews: [(ChatRoom, [ChatMessage])] = []
    private var hotRoomsListener: ListenerRegistration?
    private var hotRoomMessageListeners: [String: ListenerRegistration] = [:]
    
    //MARK: 프로필 설정 관련 기능들
    // UserProfile 문서 불러오기
    func getUserDoc() async throws -> DocumentSnapshot? {
        let querySnapshot = try await db.collection("Users")
            .whereField("email", isEqualTo: LoginManager.shared.getUserEmail)
            .limit(to: 1)
            .getDocuments()
        
        guard let user_doc = querySnapshot.documents.first else {
            print("사용자 문서 불러오기 실패")
            return nil
        }
        
        print(#function, "✅ 사용자 문서 불러오기 성공", user_doc)
        return user_doc
    }
    
    // Firebase Firestore에 UserProfile 객체 저장
    func saveUserProfileToFirestore(email: String) async throws {
        do {
            var profileData = LoginManager.shared.currentUserProfile?.toDict() ?? [:]
            profileData["createdAt"] = FieldValue.serverTimestamp()
            try await db.collection("Users").document(email).setData(profileData)

        } catch {
            throw FirebaseError.FailedToSaveProfile
        }
    }
    
//     Firebase Firestore에서 UserProfile 불러오기
    func fetchUserProfileFromFirestore(email: String) async throws -> UserProfile {
        print("fetchUserprofileFromFirestore 호출")
        
        let documentIDs = try await fetchAllDocIDs(collectionName: "Users")
        if documentIDs.isEmpty { throw FirebaseError.FailedToFetchProfile }
        
        return try await withThrowingTaskGroup(of: UserProfile?.self) { group in
            for documentID in documentIDs {
                group.addTask {
                    
                    let refToCheck = self.db.collection("Users").document(documentID).collection("\(documentID) Users").whereField("email", isEqualTo: email)
                    let snapshot = try await refToCheck.getDocuments()
                    
                    guard let data = snapshot.documents.first?.data() else { throw FirebaseError.FailedToFetchProfile }
                    
                    return UserProfile(
                        email: email,
                        nickname: data["nickname"] as? String,
                        gender: data["gender"] as? String,
                        birthdate: data["birthdate"] as? String,
                        profileImagePath: data["profileImagePath"] as? String,
                        joinedRooms: data["joinedRooms"] as? [String]
                    )
                }
            }
            
            for try await result in group {
                if let profile = result {
                    group.cancelAll()
                    return profile
                }
            }
            
            throw FirebaseError.FailedToFetchProfile
        }
        
    }
    
    func fetchUserProfiles(emails: [String]) async throws -> [UserProfile] {
        return try await withThrowingTaskGroup(of: UserProfile?.self) { group in
            for email in emails {
                group.addTask {
                    do {
                        
                        let profile = try await self.fetchUserProfileFromFirestore(email: email)
                        return profile
                        
                    } catch {
                        
                        print("\(email) 사용자 프로필 불러오기 실패: \(error)")
                        return nil
                        
                    }
                }
            }
            
            var profiles = [UserProfile]()
            for try await result in group {
                if let profile = result {
                    profiles.append(profile)
                }
            }
            
            return profiles
        }
    }
    
    func fetchAllDocIDs(collectionName: String) async throws -> [String] {
        var results = [String]()
        
        do {
            
            let querySnapshot = try await db.collection(collectionName).getDocuments()
            for document in querySnapshot.documents {
                results.append(document.documentID)
            }
            
            print(results, " 월별 문서 ID 불러오기 성공")
            return results
            
        } catch {
    
            throw FirebaseError.FailedToFetchAllDocumentIDs
        
        }
    }
    
    // 프로필 닉네임 중복 검사
    func checkDuplicate(strToCompare: String, fieldToCompare: String, collectionName: String) async throws -> Bool{
        do {
            let query = db.collection(collectionName).whereField(fieldToCompare, isEqualTo: strToCompare)
            let snapshot = try await query.getDocuments()
            
            return !snapshot.isEmpty
        } catch {
            throw FirebaseError.Duplicate
        }
    }
    
    //MARK: 채팅 방 관련 기능들
    @MainActor
    func updateRoomLastMessageAt(roomID: String, date: Date? = nil) async {
        guard !roomID.isEmpty else {
            print("❌ updateRoomLastMessageAt: roomID is empty")
            return
        }
        
        do {
            let ref = db.collection("Rooms").document(roomID)
            var updateData: [String: Any] = [:]
            
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
    
    // 특정 방 문서 불러오기
    func getRoomDoc(room: ChatRoom) async throws -> DocumentSnapshot? {
        let roomRef = db.collection("Rooms").document(room.ID ?? "")
        let room_snapshot = try await roomRef.getDocument()
        
        guard room_snapshot.exists else {
            print("방 문서 불러오기 실패")
            return nil
        }
        
        return room_snapshot

    }
    
    func fetchRoomInfo(room: ChatRoom) async throws -> ChatRoom {
        guard let roomDoc = try await getRoomDoc(room: room) else {
            throw NSError(domain: "RoomNotFound", code: 404)
        }
        
        guard let data = roomDoc.data() else {
            throw NSError(domain: "InvalidRoomData", code: 422)
        }
        
        guard
            let roomName = data["roomName"] as? String,
            let roomDescription = data["roomDescription"] as? String,
            let participants = data["participantIDs"] as? [String],
            let creatorID = data["creatorID"] as? String,
            let timestamp = data["createdAt"] as? Timestamp
        else {
            throw NSError(domain: "InvalidRoomData", code: 422)
        }
        
        let roomImagePath = data["roomImagePath"] as? String
        let id = data["ID"] as? String

        return ChatRoom(
            ID: id,
            roomName: roomName,
            roomDescription: roomDescription,
            participants: participants,
            creatorID: creatorID,
            createdAt: timestamp.dateValue(),
            roomImagePath: roomImagePath
        )
    }
    
    // 오픈 채팅 방 정보 저장
    func saveRoomInfoToFirestore(room: ChatRoom, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            var tempRoom = room
            let roomRef = db.collection("Rooms").document()
            
            // Socket.IO 서버에 방 생성 이벤트 전송
            SocketIOManager.shared.createRoom(room.roomName)
            // Socket.IO 서버에 방 참여 이벤트 전송
            SocketIOManager.shared.joinRoom(room.roomName)
            
            do {
                let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                    
                    tempRoom.ID = roomRef.documentID
                    transaction.setData(tempRoom.toDictionary(), forDocument: roomRef)
                    
                    return nil
                    
                })
                
                try await FirebaseManager.shared.add_room_participant(room: tempRoom)
                completion(.success(()))
                
            } catch {
                completion(.failure(error))
            }
        }
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
        
        roomChangeSubject.send(room)
    }
    
    // 방 이름 중복 검사
    func checkRoomName(roomName: String, completion: @escaping (Bool, Error?) -> Void) {
        db.collection("Rooms").whereField("roomName", isEqualTo: roomName).getDocuments { snapshot, error in
            if let error = error {
                completion(false, error)
                return
            }
            
            if let snapshot = snapshot, snapshot.isEmpty {
                completion(false, nil) // 중복 x
            } else {
                completion(true, nil) // 중복 o
            }
        }
    }

    private func updateHotRoomsPreviews(room: ChatRoom, messages: [ChatMessage], allRooms: [ChatRoom]) {
        var current = hotRoomsWithPreviews
        current.removeAll { $0.0.ID == room.ID }
        current.append((room, messages.sorted { $0.sentAt ?? Date() < $1.sentAt ?? Date() }))
        hotRoomsWithPreviews = allRooms.compactMap{ r in
            let msgs = current.first(where: { $0.0.ID == r.ID })?.1 ?? []
            return (r, msgs)
        }
    }
    
    private func handleMessageSnapshot(_ snapshot: QuerySnapshot?, error: Error?, room: ChatRoom, allRooms: [ChatRoom]) {
        guard let snapshot = snapshot else {
            print("HotRoom 메시지 불러오기 실패: \(error?.localizedDescription ?? "알 수 없는 에러")")
            return
        }
        
        let messages = snapshot.documents.compactMap{ try? $0.data(as: ChatMessage.self) }
        DispatchQueue.main.async {
            self.updateHotRoomsPreviews(room: room, messages: messages, allRooms: allRooms)
        }
    }
    
    private func attachMessageListener(for room: ChatRoom, roomID: String, allRooms: [ChatRoom]) {
        hotRoomMessageListeners[roomID]?.remove()
        
        let listener = db.collection("Rooms")
            .document(roomID)
            .collection("Messages")
            .order(by: "sentAt", descending: true)
            .limit(to: 3)
            .addSnapshotListener { [weak self] snapshot, error in
                self?.handleMessageSnapshot(snapshot, error: error, room: room, allRooms: allRooms)
            }
        
        hotRoomMessageListeners[roomID] = listener
    }
    
    private func updateRoomListeners(for rooms: [ChatRoom]) {
        let newIDs = Set(rooms.compactMap{ $0.ID })
        let oldIDs = Set(hotRoomMessageListeners.keys)
        let removedIDs = oldIDs.subtracting(newIDs)
        
        removedIDs.forEach { id in
            hotRoomMessageListeners[id]?.remove()
            hotRoomMessageListeners.removeValue(forKey: id)
        }
        
        for room in rooms {
            guard let roomID = room.ID else { return }
            attachMessageListener(for: room, roomID: roomID, allRooms: rooms)
        }
    }

    private func handleHotRoomsSnapshot(_ snapshot: QuerySnapshot?, error: Error?) {
        guard let snapshot = snapshot else {
            print("HotRooms 불러오기 실패: \(error?.localizedDescription ?? "알 수 없는 에러")")
            return
        }
        let rooms = snapshot.documents.compactMap { try? createRoom(from: $0) }
        updateRoomListeners(for: rooms)
    }

    func listenToHotRooms() async throws {
        detachHotRoomsListeners()

        hotRoomsListener = db.collection("Rooms")
            .order(by: "lastMessageAt", descending: true)
            .limit(to: 20)
            .addSnapshotListener { [weak self] snapshot, error in
                self?.handleHotRoomsSnapshot(snapshot, error: error)
            }
    }

    private func createRoom(from document: DocumentSnapshot) throws -> ChatRoom {
        do {
            return try document.data(as: ChatRoom.self)
        } catch {
            print("채팅방 디코딩 실패: \(error), docID: \(document.documentID)")
            throw FirebaseError.FailedToParseRoomData
        }
    }
    
    private func detachHotRoomsListeners() {
        hotRoomsListener?.remove()
        hotRoomMessageListeners.values.forEach{ $0.remove() }
        hotRoomMessageListeners.removeAll()
    }
    
    func remove_participant(room: ChatRoom) {
        remove_participant_task?.cancel()
        remove_participant_task = Task {
            do {
                
                guard let user_doc = try await getUserDoc() else { return }
                
                let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                
                    transaction.updateData(["joinedRooms": FieldValue.arrayRemove([room.roomName])], forDocument: user_doc.reference)
                    
                    return nil
                    
                })
                
                if let imageName = room.roomImagePath {
                    try await KingfisherManager.shared.cache.removeImage(forKey: imageName)
                }
                
                print("참여중인 방 강제 삭제 성공")
                remove_participant_task = nil
                
            } catch {
                
                print("방 참여자 강제 삭제 트랜젝션 실패: \(error)")
                
            }
        }
    }
    
    // 방 참여자 업데이트
    func add_room_participant(room: ChatRoom) async throws {
        add_room_participant_task?.cancel()
        add_room_participant_task = Task {
            do {
                
                guard let user_doc = try await getUserDoc(),
                      let room_doc = try await getRoomDoc(room: room) else { return }

                let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                    
                    transaction.updateData(["joinedRooms": FieldValue.arrayUnion([room.ID ?? ""])], forDocument: user_doc.reference)
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
    
    //MARK: 메시지 관련 기능
    func saveMessage(_ message: ChatMessage, _ room: ChatRoom) async throws /*-> String*/ {
        do {
            let roomDoc = try await getRoomDoc(room: room)
            let messageRef = roomDoc?.reference.collection("Messages").document() // 자동 ID 생성

            try await messageRef?.setData(message.toDict())
            
            print("메시지 저장 성공 => \(message)")
        } catch {
            print("메시지 전송 및 저장 실패")
        }
    }

    // Firestore에서 메시지 페이징과 중복 방지까지 지원하는 fetch 함수 예시
    func fetchMessagesPaged(for room: ChatRoom, pageSize: Int = 50, reset: Bool = false) async throws -> [ChatMessage] {
        // 1. 로컬 DB에서 마지막 메시지 시간 조회
        let lastTimestamp: Date? = try GRDBManager.shared.fetchLastMessageTimestamp(for: room.ID ?? "")
        let adjustedTimestamp = lastTimestamp?.addingTimeInterval(0.001) // 1ms 보정
        print(#function, "마지막 메시지 시간: ", adjustedTimestamp ?? Date())
        
        // 2. Firestore 컬렉션 경로 세팅
        let monthID = DateManager.shared.getMonthFromTimestamp(date: room.createdAt)
        let collection = db
            .collection("Rooms")
            .document(monthID)
            .collection("\(monthID) Rooms")
            .document(room.ID ?? room.roomName)
            .collection("Messages")
        
        // 3. 쿼리 생성 (sentAt 기준 오름차순, limit 적용)
        var query: Query = collection.order(by: "sentAt", descending: false)
                                     .limit(to: pageSize)
        
        // 4. reset 시 페이지네이션 초기화
        if reset {
            lastFetchedSnapshot = nil
        }
        
        // 5. 페이지네이션 조건 적용
        if let lastSnapshot = lastFetchedSnapshot {
            query = query.start(afterDocument: lastSnapshot)
        } else if let timestamp = adjustedTimestamp {
            query = query.whereField("sentAt", isGreaterThan: Timestamp(date: timestamp))
        }
        
        // 6. 쿼리 실행
        let snapshot = try await query.getDocuments()
        
        // 7. 마지막 불러온 문서 저장 (다음 페이지네이션용)
        lastFetchedSnapshot = snapshot.documents.last

        // 8. 결과 디코딩
        let messages = snapshot.documents.compactMap { doc -> ChatMessage? in
            do {
                return try doc.data(as: ChatMessage.self)
            } catch {
                print("⚠️ 디코딩 실패: \(error), docID: \(doc.documentID)")
                return nil
            }
        }

        return messages
    }
    
    func fetchAllMessages(for room: ChatRoom) async throws -> [ChatMessage] {
        print(#function, "✅ 호출 완료")

        let monthID = DateManager.shared.getMonthFromTimestamp(date: room.createdAt)
        
        guard let roomID = room.ID else {
            print("❌ room.ID 가 nil입니다.")
            return []
        }

        let messagesSnapshot = try await db
            .collection("Rooms")
            .document(monthID)
            .collection("\(monthID) Rooms")
            .document(roomID)
            .collection("Messages")
            .order(by: "sentAt", descending: false)
            .getDocuments()
        
        print("📦 불러온 메시지 개수: \(messagesSnapshot.count)")

        return messagesSnapshot.documents.compactMap { doc in
            do {
                return try doc.data(as: ChatMessage.self)
            } catch {
                print("🔥 메시지 디코딩 실패: \(error.localizedDescription) → \(doc.data())")
                return nil
            }
        }
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
