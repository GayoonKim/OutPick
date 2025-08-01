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
    
    //MARK: 프로필 설정 관련 기능들
    // UserProfile 문서 불러오기
    func getUserDoc() async throws -> QueryDocumentSnapshot? {
        let profile_created_month = DateManager.shared.getMonthFromTimestamp(date: LoginManager.shared.currentUserProfile?.createdAt ?? Date())
        let user_snapshot = try await db.collection("Users").document(profile_created_month).collection("\(profile_created_month) Users").whereField("email", isEqualTo: LoginManager.shared.getUserEmail).limit(to: 1).getDocuments()
        
        guard let user_doc = user_snapshot.documents.first else {
            print("사용자 문서 불러오기 실패")
            return nil
        }
        
        return user_doc
    }
    
    // Firebase Firestore에 UserProfile 객체 저장
    func saveUserProfileToFirestore(email: String) async throws {
        let userProfileRef = db.collection("Users")
        do {
            
            let querySnapshot = try await userProfileRef.getDocuments()
            if querySnapshot.isEmpty {
                try await userProfileRef.document(DateManager.shared.currentMonth).setData(["createAt": FieldValue.serverTimestamp()])
            }
            try await userProfileRef.document(DateManager.shared.currentMonth).collection("\(DateManager.shared.currentMonth) Users").document().setData(LoginManager.shared.currentUserProfile?.toDict() ?? [:])
            
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
            
            let documentIDs = try await fetchAllDocIDs(collectionName: collectionName)
            
            return try await withThrowingTaskGroup(of: Bool.self) { group in
                for documentID in documentIDs {
                    group.addTask { [weak self] in
                        guard let self = self else { return false }
                        
                        let refToCheck = self.db.collection(collectionName).document(documentID).collection("\(documentID) \(collectionName)").whereField(fieldToCompare, isEqualTo: strToCompare)
                        let documents = try await refToCheck.getDocuments()
                        
                        if !documents.isEmpty {
                            return true
                        }
                        
                        return false
                    }
                }
                
                for try await result in group {
                    if result {
                        group.cancelAll()
                        return true
                    }
                }
                
                return false
                
            }
            
        } catch {
            
            throw FirebaseError.Duplicate
            
        }
        
    }
    
    //MARK: 채팅 방 관련 기능들
    
    // 특정 방 문서 불러오기
    func getRoomDoc(room: ChatRoom) async throws -> QueryDocumentSnapshot? {
        
        let roomCreatedMonth = DateManager.shared.getMonthFromTimestamp(date: room.createdAt)
        print(#function, "\(roomCreatedMonth) Rooms")
        let room_snapshot = try await db.collection("Rooms").document(roomCreatedMonth).collection("\(roomCreatedMonth) Rooms").whereField("ID", isEqualTo: room.ID ?? "").limit(to: 1).getDocuments()

        guard let room_doc = room_snapshot.documents.first else {
            print("방 문서 불러오기 실패")
            return nil
        }
        
        return room_doc
        
    }
    
    func fetchRoomInfo(room: ChatRoom) async throws -> ChatRoom {
        guard let roomDoc = try await getRoomDoc(room: room) else {
            throw NSError(domain: "RoomNotFound", code: 404)
        }
        
        let data = roomDoc.data()
        
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
        print("saveRoomInfoToFirestore 시작")
        
        var tempRoom = room
        
        // 방 컬렉션에서 방 ID를 기준으로 문서 참조 생성
        let roomRef = db.collection("Rooms").document(DateManager.shared.currentMonth).collection("\(DateManager.shared.currentMonth) Rooms").document()
        Task {
            
//            let querySnapshot = try await db.collection("Rooms").getDocuments()
//            if querySnapshot.isEmpty {
//                try await db.collection("Rooms").document(DateManager.shared.currentMonth).setData(["createAt": FieldValue.serverTimestamp()])
//            }
            
            try await db.collection("Rooms").document(DateManager.shared.currentMonth).setData(["createAt": FieldValue.serverTimestamp()])

            // Socket.IO 서버에 방 생성 이벤트 전송
            SocketIOManager.shared.createRoom(room.roomName)
            // Socket.IO 서버에 방 참여 이벤트 전송 (방장)
            SocketIOManager.shared.joinRoom(room.roomName)
            
            do {
                let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                    
                    tempRoom.ID = roomRef.documentID
                    transaction.setData(tempRoom.toDictionary(), forDocument: roomRef)
                    
                    return nil
                    
                })
                
                try await FirebaseManager.shared.add_room_participant(room: room)
                
                print("saveRoomInfoToFirestore 끝")
                completion(.success(()))
                
            } catch {
                
                print("트랜잭션 실패")
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
    
    private func createRoom(data: [String:Any]) async throws -> ChatRoom {
        
        guard let ID = data["ID"] as? String,
              let roomName = data["roomName"] as? String,
              let roomDescription = data["roomDescription"] as? String,
              let participants = data["participantIDs"] as? [String],
              let creatorID = data["creatorID"] as? String,
              let timestamp = data["createdAt"] as? Timestamp,
              let roomImagePath = data["roomImagePath"] as? String else {
            print("채팅방 데이터 파싱 실패: \(data)")
            throw FirebaseError.FailedToParseRoomData
        }
        
        return ChatRoom(ID: ID, roomName: roomName, roomDescription: roomDescription, participants: participants, creatorID: creatorID, createdAt: timestamp.dateValue(), roomImagePath: roomImagePath)
    }
    
    private func processRoomChanges(documentChanges: [DocumentChange]) async throws {
        print("RoomChange 호출")
        
        do {
            try await withThrowingTaskGroup(of: (DocumentChangeType, ChatRoom).self, returning: Void.self) { group in
                for change in documentChanges {
                    group.addTask {
                        
                        let document = change.document
                        let data = document.data()
                        
                        let room = try await self.createRoom(data: data)
                        return (change.type, room)
                        
                    }
                }
                
                for try await (changeType, room) in group {
                    switch changeType {
                        
                    case .added:
                        print("추가")
                        self.chatRooms.append(room)
                        
                    case .modified:
                        print("수정")
                        if let index = self.chatRooms.firstIndex(where: { $0.roomName == room.roomName }) {
                            self.chatRooms[index] = room
                            self.roomChangeSubject.send(room)
                        }
                        
                    case .removed:
                        print("삭제")
                        self.chatRooms.removeAll(where: { $0.roomName == room.roomName })
                        remove_participant(room: room)
                    }
                }
            }
        } catch {

            for _ in 0...2 {
                
                try await self.processRoomChanges(documentChanges: documentChanges)
                
            }
        }
        
    }

    private func listenToMonthlyRoom(monthID: String) async throws -> ListenerRegistration {
        let listerner = db.collection("Rooms").document(monthID).collection("\(monthID) Rooms").addSnapshotListener { (querySnapshot, error) in
            guard let querySnapshot = querySnapshot, error == nil else {
                
                print("월별 문서 하위 컬렉션 실시간 리스너 설정 실패: \(error!.localizedDescription)")
                retry(asyncTask: { let _ = try await self.listenToMonthlyRoom(monthID: monthID )}) { result in
                    switch result {
                        
                    case .success():
                        print("월별 문서 하위 컬렉션 실시간 리스너 재설정 성공")
                        return
                        
                    case .failure(let error):
                        print ("월별 문서 하위 컬렉션 실시간 리스너 재설정 실패: \(error.localizedDescription)")
                        return
                    }
                    
                }
                return
            }
            
            let documentChanges = querySnapshot.documentChanges
            Task { try await self.processRoomChanges(documentChanges: documentChanges) }
        }
        
        print(monthID + " 월별 문서 하위 컬렉션 실시간 리스너 설정 성공")
        return listerner
    }

    private func listenToMonthlyRooms(monthIDs: [String]) async throws {
        do {
            try await withThrowingTaskGroup(of: (String, ListenerRegistration).self, returning: Void.self) { group in
                for monthID in monthIDs {
                    group.addTask {
                        
                        let listener = try await self.listenToMonthlyRoom(monthID: monthID)
                        return (monthID, listener)
                        
                    }
                }
                
                for try await (monthID, listener) in group {
                    
                    monthlyRoomListeners[monthID] = listener
                    
                }
            }
        } catch {
            retry(asyncTask: { try await self.listenToMonthlyRooms(monthIDs: monthIDs) }) { result in
                switch result {
                 
                case .success():
                    print("월별 하위 컬렉션 리스너 재설정 성공")
                    return
                    
                case .failure(let error):
                    print("월별 하위 컬렉션 리스너 재설정 실패: \(error.localizedDescription)")
                    return
                    
                }
            }
        }
    }
    
    @MainActor
    func listenToRooms() async throws{
        //기존 모든 리스너 제거
        removeAllListeners()
        
        listenToRoomsTask?.cancel()
        listenToRoomsTask = Task {
            do {
                // Rooms 컬렉션이 비어있는 경우 현재 월 문서 생성
                let roomsSnapshot = try await db.collection("Rooms").getDocuments()
                if roomsSnapshot.isEmpty {
                    
                    try await db.collection("Rooms").document(DateManager.shared.currentMonth).setData([:])
                    
                }
                
                // 모든 월별 문서 ID 불러오기
                let monthIDs = try await FirebaseManager.shared.fetchAllDocIDs(collectionName: "Rooms")
                // 모든 월별 문서의 하위 컬렉션 리스너 설정
                try await listenToMonthlyRooms(monthIDs: monthIDs)
            } catch {
                retry(asyncTask: listenToRooms) { result in
                    switch result {
                        
                    case .success():
                        print("월별 문서 불러오기 재시도 성공")
                        
                        return
                        
                    case .failure(let error):
                        print("월별 문서 목록 불러오기 실패: \(error.localizedDescription)")
                        return
                        
                    }
                }
            }
            
            listenToRoomsTask = nil
        }
    }
        
    private func removeAllListeners() {
        
        for listener in monthlyRoomListeners.values {
            listener.remove()
        }
        monthlyRoomListeners.removeAll()
        
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
                    
                    transaction.updateData(["joinedRooms": FieldValue.arrayUnion([room.roomName])], forDocument: user_doc.reference)
                    transaction.updateData(["participantIDs": FieldValue.arrayUnion([LoginManager.shared.getUserEmail])], forDocument: room_doc.reference)
                    
                    return nil
                    
                })
                
                print("참여자 업데이트 성공")
                add_room_participant_task = nil
                
                            
            } catch {
                
                print("방 참여자 업데이트 트랜젝션 실패: \(error)")
                
            }
        }
        
    }
    
    //MARK: 메시지 관련 기능
    func saveMessage(_ message: ChatMessage, _ room: ChatRoom) async throws{
        do {
            let roomDoc = try await getRoomDoc(room: room)
            try await roomDoc?.reference.collection("Messages").document().setData(message.toDict())
            
            print("메시지 저장 성공 => \(message)")
        } catch {
            print("메시지 전송 전송 및 저장 실패")
        }
    }

    func fetchMessages(after date: Date?, for room: ChatRoom) async throws -> [ChatMessage] {
        print(#function, "✅ 호출 완료")
        
        let monthID = DateManager.shared.getMonthFromTimestamp(date: room.createdAt)
        
        let collection = db
            .collection("Rooms")
            .document(monthID)
            .collection("\(monthID) Rooms")
            .document(room.ID ?? room.roomName)
            .collection("Messages")
        
        var query: Query = collection.order(by: "sentAt", descending: false)
        
        if let date = date {
            query = query.whereField("sentAt", isGreaterThan: Timestamp(date: date))
        }
        
        let snapshot = try await query.getDocuments()
        
        print("📦 불러온 메시지 개수: \(snapshot.count)")
        
        return snapshot.documents.compactMap { doc in
            do {
                return try doc.data(as: ChatMessage.self)
            } catch {
                print("🔥 메시지 디코딩 실패: \(error.localizedDescription) → \(doc.data())")
                return nil
            }
        }
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
