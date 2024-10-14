//
//  FirestoreManager.swift
//  OutPick
//
//  Created by 김가윤 on 10/10/24.
//

import Foundation
import FirebaseFirestore
import FirebaseStorage

class FirestoreManager {
    
    // FirestoreManager의 싱글톤 인스턴스
    static let shared = FirestoreManager()
    
    // Firestore 인스턴스
    let db = Firestore.firestore()
    
    // Firebase Firestore에 UserProfile 객체 저장
    func saveUserProfileToFirestore(userProfile: UserProfile, email: String, completion: @escaping (Error?) -> Void) {
        let userProfileRef = db.collection("Users").document(email)
        
        userProfileRef.setData(userProfile.toDict()) { error in
            completion(error)
        }
    }
    
    // Firebase Firestore에서 UserProfile 불러오기
    func fetchUserProfileFromFirestore(email: String, completion: @escaping (Result<UserProfile, Error>) -> Void) {
        let userProfileRef = db.collection("Users").document(email)
        
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
    
    // Firebase Storage에 프로필 사진 저장 후 URL 반환 함수
    func uploadImage(image: UIImage, imageName: String, type: String, completion: @escaping (Result<String, Error>) -> Void) {
        let storageRef = Storage.storage().reference()
        let imageRef = storageRef.child("\(type)/\(imageName).jpg")
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(NSError(domain: "ImageConversion", code: -1, userInfo: nil)))
            return
        }
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        imageRef.putData(imageData, metadata: metadata) { metadata, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            imageRef.downloadURL { url, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                if let downloadURL = url?.absoluteString {
                    completion(.success(downloadURL))
                } else {
                    completion(.failure(NSError(domain: "DownloadURL", code: -1, userInfo: nil)))
                }
            }
        }
    }
    
    // 프로필 닉네임 중복 검사
    func checkNicknameDuplicate(nickname: String, completion: @escaping (Bool, Error?) -> Void) {
        db.collection("Users").whereField("nickname", isEqualTo: nickname).getDocuments { snapshot, error in
            if let error = error {
                completion(false, error)
                return
            }
            
            if let snapshot = snapshot, snapshot.isEmpty {
                completion(false, nil) // 닉네임 중복 x
            } else {
                completion(true, nil) // 닉네임 중복 o
            }
        }
    }
    
    // 오픈 채팅 방 정보 저장
    func saveRoomInfoToFirestore(room: ChatRoom, completion: @escaping (Result<Void, Error>) -> Void) {
        // 방 컬렉션에서 방 ID를 기준으로 문서 참조 생성
        let roomRef = db.collection("Rooms").document(room.roomName)
        
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
