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

class FirebaseManager {
    
    private init() {}
    
    // FirestoreManager의 싱글톤 인스턴스
    static let shared = FirebaseManager()
    
    // Firestore 인스턴스
    let db = Firestore.firestore()
    
    // Storage 인스턴스
    let storage = Storage.storage()
    
    // 채팅방 목록
    private var chatRooms: [ChatRoom] = []
    private var roomsListener: ListenerRegistration?
    private var monthlyRoomListeners: [String: ListenerRegistration] = [:]
    
    private var listenToRoomsTask: Task<Void, Never>? = nil
    private var fetchProfileTask: Task<Void, Never>? = nil
    private var saveUserProfileTask: Task<Void, Never>? = nil
    private var updateRoomParticipantTask: Task<Void, Never>? = nil
    
    deinit {
        listenToRoomsTask?.cancel()
        fetchProfileTask?.cancel()
        saveUserProfileTask?.cancel()
        updateRoomParticipantTask?.cancel()
    }
    
    // 채팅방 읽기 전용 접근자 제공
    var currentChatRooms: [ChatRoom] {
        return chatRooms
    }
    
    //MARK: 프로필 설정 관련 기능들
    // Firebase Firestore에 UserProfile 객체 저장
    func saveUserProfileToFirestore(email: String) async throws {
        let userProfileRef = db.collection("Users")
        do {
            
            let querySnapshot = try await userProfileRef.getDocuments()
            if querySnapshot.isEmpty {
                try await userProfileRef.document(DateManager.shared.currentMonth).setData([:])
            }
            try await userProfileRef.document(DateManager.shared.currentMonth).collection("\(DateManager.shared.currentMonth) Users").document().setData(UserProfile.shared.toDict())
            
        } catch {
            
            throw FirebaseError.FailedToSaveProfile
            
        }
    }
    
    // Firebase Firestore에서 UserProfile 불러오기
    func fetchUserProfileFromFirestore(email: String, completion: @escaping (Result<UserProfile, Error>) -> Void) {
        
        print("fetchUserprofileFromFirestore 호출")
        
        fetchProfileTask?.cancel()
        
        fetchProfileTask = Task {
            do {
                
                let documentIDs = try await fetchAllDocIDs(collectionName: "Users")
                
                if documentIDs.isEmpty {
                    throw FirebaseError.FailedToFetchAllDocumentIDs
                }
                
                
                return try await withThrowingTaskGroup(of: UserProfile.self) { group in
                    for documentID in documentIDs {
                        group.addTask {
                            
                            let refToCheck = self.db.collection("Users").document(documentID).collection("\(DateManager.shared.currentMonth) Users").whereField("email", isEqualTo: email)
                            let snapshot = try await refToCheck.getDocuments()
                            
                            guard let data = snapshot.documents.first?.data() else {
                                throw FirebaseError.FailedToFetchProfile
                            }

                            let profile = UserProfile.shared
                            profile.nickname = data["nickname"] as? String
                            profile.gender = data["gender"] as? String
                            profile.birthdate = data["birthdate"] as? String
                            profile.profileImageName = data["profileImageName"] as? String
                            profile.joinedRooms = data["joinedRooms"] as? [String]
                    
                            return profile
                            
                        }
                    }
                    
                    for try await profile in group {
                        
                        if let _ = profile.nickname {
                            completion(.success(profile))
                            group.cancelAll()
                        }
                        
                    }
                    
                }
                
            } catch {
            
                completion(.failure(error))
                
            }
            
            fetchProfileTask?.cancel()
            
        }
        
    }
    
    func fetchAllDocIDs(collectionName: String) async throws -> [String] {
        
        var results = [String]()
        
        do {
            
            let querySnapshot = try await db.collection(collectionName).getDocuments()
            for document in querySnapshot.documents {
                results.append(document.documentID)
            }
            
            return results
            
        } catch {
    
            throw FirebaseError.FailedToFetchAllDocumentIDs
            
        }
        
    }
    
    // 프로필 닉네임 중복 검사
    func checkDuplicate(strToCompare: String, fieldToCompare: String, collectionName: String/*, completion: @escaping (Bool, Error?) -> Void*/) async throws -> Bool{
        
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
    // 오픈 채팅 방 정보 저장
    func saveRoomInfoToFirestore(room: ChatRoom, completion: @escaping (Result<Void, Error>) -> Void) {
        print("saveRoomInfoToFirestore 시작")
        
        // 방 컬렉션에서 방 ID를 기준으로 문서 참조 생성
        let roomRef = db.collection("Rooms").document(DateManager.shared.currentMonth).collection("\(DateManager.shared.currentMonth) Rooms").document()
        Task {
            
            let querySnapshot = try await db.collection("Rooms").getDocuments()
            if querySnapshot.isEmpty{
                try await db.collection("Rooms").document(DateManager.shared.currentMonth).setData([:])
            }
            
            do {
                let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                    
                    transaction.setData(room.toDictionary(), forDocument: roomRef)
                    completion(.success(()))
                    return nil
                    
                })
                
                FirebaseManager.shared.updateRoomParticipant(room: room, isAdding: true)
                
                print("saveRoomInfoToFirestore 끝")
                
            } catch {
                
                print("트랜잭션 실패")
                completion(.failure(error))
                
            }
    
        }

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
        
        guard let roomName = data["roomName"] as? String,
              let roomDescription = data["roomDescription"] as? String,
              let participants = data["participantIDs"] as? [String],
              let creatorID = data["creatorID"] as? String,
              let timestamp = data["createdAt"] as? Timestamp,
              let roomImageName = data["roomImageName"] as? String else {
            print("채팅방 데이터 파싱 실패: \(data)")
            throw FirebaseError.FailedToParseRoomData
        }
        
        Task {
            do {
                let _ = try await FirebaseStorageManager.shared.fetchImageFromStorage(image: roomImageName, location: ImageLocation.RoomImage, createdDate: timestamp.dateValue())
            } catch {
                retry(asyncTask: { let _ = try await FirebaseStorageManager.shared.fetchImageFromStorage(image: roomImageName, location: ImageLocation.RoomImage, createdDate: timestamp.dateValue())  }) { result in
                    switch result {
                    case .success():
                        print("이미지 캐싱 재시도 성공")
                        return
                    case .failure(let error):
                        print("이미지 캐싱 재시도 실패: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        return ChatRoom(roomName: roomName, roomDescription: roomDescription, participants: participants, creatorID: creatorID, createdAt: timestamp.dateValue(), roomImageName: roomImageName)
        
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
                        }
                        
                    case .removed:
                        print("삭제")
                        self.chatRooms.removeAll(where: { $0.roomName == room.roomName })
//                        try await self.updateRoomParticipant(room: room, isAdding: false)
//                        try await ImageCache.default.removeImage(forKey: room.roomImageName ?? "")
                        
                    }
                    
                    NotificationCenter.default.post(name: .chatRoomsUpdated, object: nil, userInfo: ["rooms": self.chatRooms])
                    
                }
            }
        } catch {
            
            retry(asyncTask: { try await self.processRoomChanges(documentChanges: documentChanges)}) { result in
                switch result {
                    
                case .success():
                    print("모든 월별 문서 하위 컬렉션 방 문서들 불러오기 재시도 성공")
                    return
                    
                case .failure(let error):
                    print ("모든 월별 문서 하위 컬렉션 방 문서들 불러오기 재시도 실패: \(error.localizedDescription)")
//                    AlertManager.showAlert(title: "네트워크 오류", message: "네트워크 오류로 오픈채팅 목록을 불러오는데 실패했습니다. 네트워크 연결을 확인해 주세요.", viewController: self)
                    return
                    
                }
            }
            
        }
        
    }
    
    private func processAllRooms(documents: [QueryDocumentSnapshot]) async throws {
        
        do {
            try await withThrowingTaskGroup(of: ChatRoom.self, returning: Void.self) { group in
                for document in documents {
                    group.addTask {
                        
                        let data = document.data()
                        let chatRoom = try await self.createRoom(data: data)
                        
                        return chatRoom
                        
                    }
                }
                
                for try await room in group {
                    self.chatRooms.append(room)
    
                }
                
                
            }
            
            NotificationCenter.default.post(name: .chatRoomsUpdated, object: nil, userInfo: ["rooms": self.chatRooms])
            
        } catch {
            retry(asyncTask: { try await self.processAllRooms(documents: documents)}) { result in
                switch result {
                    
                case .success():
                    print("모든 월별 문서 하위 컬렉션 방 문서들 불러오기 재시도 성공")
                    return
                    
                case .failure(let error):
                    print ("모든 월별 문서 하위 컬렉션 방 문서들 불러오기 재시도 실패: \(error.localizedDescription)")
//                    AlertManager.showAlert(title: "네트워크 오류", message: "네트워크 오류로 오픈채팅 목록을 불러오는데 실패했습니다. 네트워크 연결을 확인해 주세요.", viewController: self)
                    return
                    
                }
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
//                        AlertManager.showAlert(title: "네트워크 오류", message: "네트워크 오류로 오픈채팅 목록을 불러오는데 실패했습니다. 네트워크 연결을 확인해 주세요.", viewController: self)
                        return
                    }
                }
                return
            }
            
            if querySnapshot.documentChanges.isEmpty {
                let documents = querySnapshot.documents
                Task {
                    try await self.processAllRooms(documents: documents)
                }
                
            } else {
                let documentChanges = querySnapshot.documentChanges
                Task {
                    try await self.processRoomChanges(documentChanges: documentChanges)
                }
            }
            
        }
        
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
    
    // 방 참여자 업데이트
    func updateRoomParticipant(room: ChatRoom, isAdding: Bool) {
        
        print("updateRoomParticipant 시작")
        updateRoomParticipantTask?.cancel()
        
        let roomCreatedMonth = DateManager.shared.getMonthFromTimestamp(date: room.createdAt)
        let profileCreatedMonth = DateManager.shared.getMonthFromTimestamp(date: UserProfile.shared.createdAt)
        
        updateRoomParticipantTask = Task {
            do {
        
                let room_snapshot = try await db.collection("Rooms").document(roomCreatedMonth).collection("\(roomCreatedMonth) Rooms").whereField("roomName", isEqualTo: room.roomName).limit(to: 1).getDocuments()
                let user_snapshot = try await db.collection("Users").document(profileCreatedMonth).collection("\(profileCreatedMonth) Users").whereField("email", isEqualTo: LoginManager.shared.getUserEmail).limit(to: 1).getDocuments()
                
                guard let roomDocument = room_snapshot.documents.first,
                      let userDocument = user_snapshot.documents.first else {
                    print("사용자 또는 방 문서 불러오기 실패")
                    return
                }
                
                let room_ref = roomDocument.reference
                let user_ref = userDocument.reference
                
                let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                    
                    if isAdding {
                        transaction.updateData(["joinedRooms": FieldValue.arrayUnion([room.roomName])], forDocument: user_ref)
                        transaction.updateData(["participantIDs": FieldValue.arrayUnion([LoginManager.shared.getUserEmail])], forDocument: room_ref)
                    } else {
                        transaction.updateData(["joinedRooms": FieldValue.arrayRemove([room.roomName])], forDocument: user_ref)
                        transaction.updateData(["participantIDs": FieldValue.arrayRemove([LoginManager.shared.getUserEmail])], forDocument: room_ref)
                    }
                    
                    return nil
                })
                
                print("참여자 업데이트 성공")
                updateRoomParticipantTask = nil
                            
            } catch {
                
                print("방 참여자 업데이트 트랜젝션 실패: \(error)")
                
            }
        }
        
        print("updateRoomParticipant 끝")
        
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
