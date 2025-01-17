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
    private var roomsMap: [String: ChatRoom] = [:]
    private var roomsListener: ListenerRegistration?
    private var monthlyRoomListeners: [String: ListenerRegistration] = [:]
    
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
            try await userProfileRef.document(DateManager.shared.currentMonth).collection("\(DateManager.shared.currentMonth) Users").document(email).setData(UserProfile.shared.toDict())
            
        } catch {
            
            throw FirebaseError.FailedToSaveProfile
            
        }
    }
    
    // Firebase Firestore에서 UserProfile 불러오기
    func fetchUserProfileFromFirestore(email: String, completion: @escaping (Result<UserProfile, Error>) -> Void) {
        
        Task {
            do {
                
                let documentIDs = try await fetchAllDocIDs(collectionName: "Users")
                return try await withThrowingTaskGroup(of: UserProfile.self) { group in
                    for documentID in documentIDs {
                        group.addTask {
                            
                            let refToCheck = self.db.collection("Users").document(documentID).collection("\(DateManager.shared.currentMonth) Users").document(email)
                            let snapshot = try await refToCheck.getDocument()
                            
                            guard let data = snapshot.data() else {
                                throw FirebaseError.FailedToFetchProfile
                            }
                            
                            let profile = UserProfile.shared
                            profile.id = data["id"] as? String
                            profile.nickname = data["nickname"] as? String
                            profile.gender = data["gender"] as? String
                            profile.birthdate = data["birthdate"] as? String
                            profile.profileImageName = data["profileImageName"] as? String
                            profile.joinedRooms = data["joinedRooms"] as? [String]
                            
                            return profile
                            
                        }
                    }
                    
                    for try await result in group {
                        if let _ = result.nickname {
                            completion(.success(result))
                            group.cancelAll()
                        }
                    }
                    
                }
                
            } catch {
                
                completion(.failure(FirebaseError.FailedToFetchProfile))
                
            }
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
            
            throw FirebaseError.FailedToFetchProfileDocumentID
            
        }
        
    }
    
    // 프로필 닉네임 중복 검사
    func checkDuplicate(strToCompare: String, fieldToCompare: String, collectionName: String/*, completion: @escaping (Bool, Error?) -> Void*/) async throws -> Bool{
        
        do {
            
            let documentIDs = try await fetchAllDocIDs(collectionName: collectionName)
            
            return try await withThrowingTaskGroup(of: Bool.self) { group in
                for documentID in documentIDs {
                    group.addTask {
                        
                        let refToCheck = self.db.collection(collectionName).document(documentID).collection("\(documentID) \(collectionName)").whereField(fieldToCompare, isEqualTo: strToCompare)
                        let document = try await refToCheck.getDocuments()
                        
                        if !document.isEmpty {
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
            
            throw FirebaseError.NickNameDuplicate
            
        }
        
    }
    
    //MARK: 채팅 방 관련 기능들
    // 오픈 채팅 방 정보 저장
    func saveRoomInfoToFirestore(room: ChatRoom, completion: @escaping (Result<Void, Error>) -> Void) {
        
        // 방 컬렉션에서 방 ID를 기준으로 문서 참조 생성
        let roomRef = db.collection("Rooms").document(DateManager.shared.currentMonth).collection("\(DateManager.shared.currentMonth) Rooms").document(room.roomName)
        Task {
            
            let querySnapshot = try await db.collection("Rooms").getDocuments()
            if querySnapshot.isEmpty{
                try await db.collection("Rooms").document(DateManager.shared.currentMonth).setData([:])
            }
            
            do {
                let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                    
//                    let sfDocument: DocumentSnapshot
                    
//                    do {
//                        try sfDocument = transaction.getDocument(roomRef)
//                    } catch let fetchError as NSError {
//                        errorPointer?.pointee = fetchError
//                        throw fetchError
//                        return nil
//                    }
                    
                    transaction.setData(room.toDictionary(), forDocument: roomRef)
                    completion(.success(()))
                    return nil
                })
                
                print("트랜잭션 성공")
                
            } catch {
                
                print("트랜잭션 실패")
                completion(.failure(error))
                
            }
            
        }
        
        
        
//        let roomRef = db.collection("Rooms").document("\(DateManager.shared.currentMonth)").collection("\(DateManager.shared.currentMonth) Rooms").document(room.roomName)
//        let roomRef = db.collection("Rooms").document(room.roomName)
        
        
        
        // Rooms 컬렉션이 존재하는지 확인하고 없으면 생성
//        db.collection("Rooms").getDocuments { [weak self] (snapshot, error) in
//            guard let self = self else { return }
//            
//            db.runTransaction({ (transaction, errorPointer) -> Any? in
//                // 방 정보가 이미 존재하는지 확인
//                do {
//                    let roomSnapshot = try transaction.getDocument(roomRef)
//                    
//                    // 방이 이미 존재하면 오류 처리 (방 이름 중복 방지)
//                    if roomSnapshot.exists {
//                        errorPointer?.pointee = NSError(domain: "ChatAppErrorDomain", code: 1, userInfo: [
//                            NSLocalizedDescriptionKey: "방 이름 중복"
//                        ])
//                        return nil
//                    }
//                    
//                    // Firestore에 방 데이터 추가
//                    transaction.setData(room.toDictionary(), forDocument: roomRef)
//                    
//                } catch {
//                    // 트랜잭션 실패 처리
//                    errorPointer?.pointee = error as NSError
//                    return nil
//                }
//                
//                return nil
//            }) { (object, error) in
//                // 트랜잭션 완료 처리
//                if let error = error {
//                    print("트랜잭션 실패: \(error)")
//                    completion(.failure(error))
//                } else {
//                    print("트랜잭션 성공")
//                    completion(.success(()))
//                }
//            }
//        }
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
    
    // 실시간 채팅방 리스너 설정
    func listenForChatRooms(completion: @escaping ([ChatRoom]) -> Void) {
        print("listenForChatRooms 호출")
        
        removeAllListeners()
        
        roomsListener = db.collection("Rooms").addSnapshotListener { [weak self] snapshot, error in
        
            guard let self = self, let documents = snapshot?.documents else {
                print("월별 문서 목록 불러오기 실패: \(error!.localizedDescription)")
                return
            }
            
            
            
        }
        
            
            
        }
        
//        // 기존 리스너 있으면 제거
//        roomsListener?.remove()
//        
//        roomsListener = db.collection("Rooms").addSnapshotListener { [weak self] snapshot, error in
//            guard let self = self,
//                  let documents = snapshot?.documents else {
//                print("채팅방 목록 불러오기 실패: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//            
//            let _ = documents.compactMap { document -> ChatRoom? in
//                
//                let data = document.data()
//                
//                guard let roomName = data["roomName"] as? String,
//                      let roomDescription = data["roomDescription"] as? String,
//                      let participants = data["participantIDs"] as? [String],
//                      let creatorID = data["creatorID"] as? String,
//                      let timestamp = data["createdAt"] as? Timestamp,
//                      let roomImageName = data["roomImageName"] as? String else {
//                    return nil
//                }
//                
//                let chatRoom = ChatRoom(
//                    id: document.documentID,
//                    roomName: roomName,
//                    roomDescription: roomDescription,
//                    participants: participants,
//                    creatorID: creatorID,
//                    createdAt: timestamp.dateValue(),
//                    roomImageName: roomImageName
//                )
//                
//                
//    
//                // 방 대표 사진 미리 캐싱
//                Task {
//                    do {
//                        let _ = try await FirebaseStorageManager.shared.fetchImageFromStorage(image: roomImageName, location: ImageLocation.RoomImage, createdDate: chatRoom.createdAt)
//                    } catch StorageError.FailedToFetchImage {
//                        guard let error = error else { return }
//                        print("이미지 불러오기 실패: \(error.localizedDescription)")
//                    }
//                }
//                self.chatRooms.append(chatRoom)
//                return chatRoom
//            }
//            
//            // UI 업데이트를 위한 노티피케이션 발송
//            NotificationCenter.default.post(name: .chatRoomsUpdated, object: nil, userInfo: ["rooms": self.chatRooms])
//            completion(self.chatRooms)
//        }
        
//    }
    
    // 채팅방 리스너 제거
    private func removeAllListeners() {
        roomsListener?.remove()
        roomsListener = nil
    }
    
    // 방 참여자 업데이트
    func updateRoomParticipants(room: ChatRoom) async throws {
        
        let roomCreatedMonth = DateManager.shared.getMonthFromTimestamp(date: room.createdAt)
        let profileCreatedMonth = DateManager.shared.getMonthFromTimestamp(date: UserProfile.shared.createdAt)
        
        let user_ref = db.collection("Users").document(roomCreatedMonth).collection("\(roomCreatedMonth) Users").document(LoginManager.shared.getUserEmail)
        let room_ref = db.collection("Rooms").document(profileCreatedMonth).collection("\(profileCreatedMonth) Rooms").document(room.roomName)
        
        do {
            
            let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                
                transaction.updateData(["joinedRooms": FieldValue.arrayUnion([room.roomName])], forDocument: user_ref)
                transaction.updateData(["participantIDs": FieldValue.arrayUnion([LoginManager.shared.getUserEmail])], forDocument: room_ref)
                
                return nil
            })
            
        } catch {
            
            print("방 참여자 업데이트 트랜젝션 실패: \(error)")
            try await updateRoomParticipants(room: room)
            
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
