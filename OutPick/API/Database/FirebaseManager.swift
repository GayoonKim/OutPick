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
    
    // 채팅방 읽기 전용 접근자 제공
    var currentChatRooms: [ChatRoom] {
        return chatRooms
    }
    
    //MARK: 프로필 설정 관련 기능들
    // Firebase Firestore에 UserProfile 객체 저장
    func saveUserProfileToFirestore(userProfile: UserProfile, email: String/*, completion: @escaping (Error?) -> Void*/) async throws {
//        let userProfileRef = db.collection("Users").document(email)
        let userProfileRef = db.collection("Users").document(DateManager.shared.currentMonth).collection("\(DateManager.shared.currentMonth) Users").document(email)
        
//        userProfileRef.setData(userProfile.toDict()) { error in
//            completion(error)
//        }
        
        try await userProfileRef.setData(userProfile.toDict(), merge: true)
        
    }
    
    // Firebase Firestore에서 UserProfile 불러오기
    func fetchUserProfileFromFirestore(email: String, completion: @escaping (Result<UserProfile, Error>) -> Void) /*async throws -> UserProfile?*/ {
        let userProfileRef = db.collection("Users").document(DateManager.shared.currentMonth).collection("\(DateManager.shared.currentMonth) Users").document(email)
        
//        let document = try await userProfileRef.getDocument()
//        
//        guard let data = document.data() else {
//            return nil
//        }
//        
//        do {
//            
//            let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
//            let userProfile = try JSONDecoder().decode(UserProfile.self, from: jsonData)
//            return userProfile
//            
//        } catch let error {
//            
//            print("사용자 프로필 디코딩 실패: \(error.localizedDescription)")
//            throw error
//            
//        }
        
        userProfileRef.getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = snapshot?.data() else {
                completion(.failure(NSError(domain: "NoData", code: -1, userInfo: nil)))
                return
            }
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
                let userProfile = try JSONDecoder().decode(UserProfile.self, from: jsonData)
                completion(.success(userProfile))
            } catch let error {
                completion(.failure(error))
            }
        }
    }
    
    // 프로필 닉네임 중복 검사
    func checkNicknameDuplicate(nickname: String/*, completion: @escaping (Bool, Error?) -> Void*/) async throws -> Bool{
        
        do {
            
            let nickNameDocRef = db.collection("Users").document(DateManager.shared.currentMonth).collection("\(DateManager.shared.currentMonth) Users").whereField("nickname", isEqualTo: nickname)
            let document = try await nickNameDocRef.getDocuments()
            
            if document.isEmpty {
                return false
            } else {
                return true
            }
            
        } catch {
            
            throw FirebaseError.NickNameDuplicate
            
        }
        
//        db.collection("Users").whereField("nickname", isEqualTo: nickname).getDocuments { snapshot, error in
//            
//            if let error = error {
//                completion(false, error)
//                return
//            }
//            
//            if let snapshot = snapshot, snapshot.isEmpty {
//                completion(false, nil) // 닉네임 중복 x
//            } else {
//                completion(true, nil) // 닉네임 중복 o
//            }
//            
//        }
        
    }
    
    //MARK: 채팅 방 관련 기능들
    // 오픈 채팅 방 정보 저장
    func saveRoomInfoToFirestore(room: ChatRoom, completion: @escaping (Result<Void, Error>) -> Void) {
        // 방 컬렉션에서 방 ID를 기준으로 문서 참조 생성
        let roomRef = db.collection("Rooms").document(room.roomName)
        
        // Rooms 컬렉션이 존재하는지 확인하고 없으면 생성
        db.collection("Rooms").getDocuments { [weak self] (snapshot, error) in
            guard let self = self else { return }
            
            db.runTransaction({ (transaction, errorPointer) -> Any? in
                // 방 정보가 이미 존재하는지 확인
                do {
                    let roomSnapshot = try transaction.getDocument(roomRef)
                    
                    // 방이 이미 존재하면 오류 처리 (방 이름 중복 방지)
                    if roomSnapshot.exists {
                        errorPointer?.pointee = NSError(domain: "ChatAppErrorDomain", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: "방 이름 중복"
                        ])
                        return nil
                    }
                    
                    // Firestore에 방 데이터 추가
                    transaction.setData(room.toDictionary(), forDocument: roomRef)
                    
                } catch {
                    // 트랜잭션 실패 처리
                    errorPointer?.pointee = error as NSError
                    return nil
                }
                
                return nil
            }) { (object, error) in
                // 트랜잭션 완료 처리
                if let error = error {
                    print("트랜잭션 실패: \(error)")
                    completion(.failure(error))
                } else {
                    print("트랜잭션 성공")
                    completion(.success(()))
                }
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
    
    // 실시간 채팅방 리스너 설정
    func listenForChatRooms(completion: @escaping ([ChatRoom]) -> Void) {
        // 기존 리스너 있으면 제거
        roomsListener?.remove()
        
        roomsListener = db.collection("Rooms").addSnapshotListener { [weak self] snapshot, error in
            guard let self = self,
                  let documents = snapshot?.documents else {
                print("채팅방 목록 불러오기 실패: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            self.chatRooms = documents.compactMap { document -> ChatRoom? in

                let data = document.data()
                    
                guard let roomName = data["roomName"] as? String,
                      let roomDescription = data["roomDescription"] as? String,
                      let participants = data["participantIDs"] as? [String],
                      let creatorID = data["creatorID"] as? String,
                      let timestamp = data["createdAt"] as? Timestamp,
                      let roomImageName = data["roomImageName"] as? String else {
                    return nil
                }
                    
                let chatRoom = ChatRoom(
                    id: document.documentID,
                    roomName: roomName,
                    roomDescription: roomDescription,
                    participants: participants,
                    creatorID: creatorID,
                    createdAt: timestamp.dateValue(),
                    roomImageName: roomImageName
                )
                
                // 방 대표 사진 미리 캐싱
                Task {
                    do {
                        let _ = try await FirebaseStorageManager.shared.fetchImageFromStorage(image: roomImageName, location: ImageLocation.RoomImage)
                    } catch StorageError.FailedToFetchImage {
                        guard let error = error else { return }
                        print("이미지 불러오기 실패: \(error.localizedDescription)")
                    }
                }
                
                return chatRoom
            }
            
            // UI 업데이트를 위한 노티피케이션 발송
            NotificationCenter.default.post(name: .chatRoomsUpdated, object: nil, userInfo: ["rooms": self.chatRooms])
            
            completion(self.chatRooms)
        }

    }
    
    // 채팅방 리스너 제거
    func removeChatRoomsListener() {
        roomsListener?.remove()
        roomsListener = nil
    }
    
    // 방 참여자 업데이트
    func updateRoomParticipants(roomName: String, email: String) async {
        
        let user_ref = db.collection("Users").document(email)
        let room_ref = db.collection("Rooms").document(roomName)
        
        do {
            
            let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                
                transaction.updateData(["joinedRooms": FieldValue.arrayUnion([roomName])], forDocument: user_ref)
                transaction.updateData(["participantIDs": FieldValue.arrayUnion([email])], forDocument: room_ref)
                
                return nil
            })
            
        } catch {
            
            print("방 참여자 업데이트 트랜젝션 실패: \(error)")
            
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
