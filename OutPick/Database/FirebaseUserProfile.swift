//
//  Firebase.swift
//  OutPick
//
//  Created by 김가윤 on 8/15/24.
//

import UIKit
import FirebaseStorage
import FirebaseFirestore

// Firebase Firestore에 UserProfile 객체 저장
func saveUserProfileToFirestore(userProfile: UserProfile, email: String, completion: @escaping (Error?) -> Void) {
    
    let db = Firestore.firestore()
    let userProfileRef = db.collection("Users").document(email)
    
    userProfileRef.setData(userProfile.toDict()) { error in
        completion(error)
    }

}

// Firebase Firestore에서 UserProfile 불러오기
func fetchUserProfileFromFirestore(email: String, completion: @escaping (Result<UserProfile, Error>) -> Void) {
    let db = Firestore.firestore()
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
func uploadProfileImage(image: UIImage, email: String, completion: @escaping (Result<String, Error>) -> Void) {
    let storageRef = Storage.storage().reference()
    let imageRef = storageRef.child("profileImages/\(email).jpg")
    
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

// 닉네임 중복 검사
func checkNicknameDuplicate(nickname: String, completion: @escaping (Bool, Error?) -> Void) {
    let db = Firestore.firestore()
    
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


