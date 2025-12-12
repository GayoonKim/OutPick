//
//  UserProfileRepository.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import Combine
import FirebaseFirestore

final class UserProfileRepository: UserProfileRepositoryProtocol {
    private let db: Firestore
    
    // Users/{email} 프로필 스냅샷 리스너 캐시
    private var userProfileListeners: [String: ListenerRegistration] = [:]
    // Users/{email} 프로필 변경 스트림(Combine)
    private var userProfileSubjects: [String: PassthroughSubject<UserProfile, Error>] = [:]
    
    init(db: Firestore) {
        self.db = db
    }
    
    deinit {
        // 모든 리스너 정리
        userProfileListeners.values.forEach { $0.remove() }
        userProfileSubjects.values.forEach { $0.send(completion: .finished) }
    }
    
    func listenToUserProfile(email: String) {
        if let _ = userProfileListeners[email] { return }
        
        // subject 없으면 생성
        let subject: PassthroughSubject<UserProfile, Error>
        if let s = userProfileSubjects[email] {
            subject = s
        } else {
            let s = PassthroughSubject<UserProfile, Error>()
            userProfileSubjects[email] = s
            subject = s
        }
        
        let docRef = db.collection("Users").document(email)
        let listener = docRef.addSnapshotListener { snapshot, error in
            if let error = error {
                subject.send(completion: .failure(error))
                return
            }
            
            guard let snapshot = snapshot, snapshot.exists else {
                let err = NSError(domain: "UserProfileRepository",
                                  code: 404,
                                  userInfo: [NSLocalizedDescriptionKey: "UserProfile 문서가 존재하지 않습니다."])
                subject.send(completion: .failure(err))
                return
            }
            
            do {
                let profile = try snapshot.data(as: UserProfile.self)
                
                // ✅ 1) 내 프로필이면 LoginManager만 갱신하고 subject로는 전파하지 않음
                let myEmail = LoginManager.shared.getUserEmail
                if profile.email == myEmail || email == myEmail {
                    Task { @MainActor in
                        LoginManager.shared.setCurrentUserProfile(profile)
                    }
                    return
                }
                
                // ✅ 2) 타인 프로필이면 subject로 전파
                subject.send(profile)
                
            } catch {
                subject.send(completion: .failure(error))
            }
        }
        
        userProfileListeners[email] = listener
        print(#function, "프로필 실시간 리스너 설정 갱신", userProfileListeners)
    }
    
    func userProfilePublisher(email: String) -> AnyPublisher<UserProfile, Error> {
        // 1) subject 없으면 생성/캐시
        let subject: PassthroughSubject<UserProfile, Error>
        if let s = userProfileSubjects[email] {
            subject = s
        } else {
            let s = PassthroughSubject<UserProfile, Error>()
            userProfileSubjects[email] = s
            subject = s
        }
        
        // 2) 리스너 없으면 시작
        if userProfileListeners[email] == nil {
            listenToUserProfile(email: email)
        }
        
        // 3) 외부에는 Publisher로만 노출
        return subject.eraseToAnyPublisher()
    }
    
    func stopListenUserProfile(email: String) {
        if let listener = userProfileListeners[email] {
            listener.remove()
            userProfileListeners.removeValue(forKey: email)
        }
        
        if let subject = userProfileSubjects[email] {
            subject.send(completion: .finished)
            userProfileSubjects.removeValue(forKey: email)
        }
    }
    
    func saveUserProfileToFirestore(email: String) async throws {
        do {
            var profileData = LoginManager.shared.currentUserProfile?.toDict() ?? [:]
            profileData["createdAt"] = FieldValue.serverTimestamp()
            try await db.collection("Users").document(email).setData(profileData)
        } catch {
            throw FirebaseError.FailedToSaveProfile
        }
    }
    
    func fetchUserProfileFromFirestore(email: String) async throws -> UserProfile {
        print("fetchUserProfileFromFirestore 호출")
        
        let docRef = db.collection("Users").document(email)
        let snapshot = try await docRef.getDocument()
        guard let data = snapshot.data() else {
            throw FirebaseError.FailedToFetchProfile
        }
        
        return UserProfile(
            email: data["email"] as? String ?? email,
            nickname: data["nickname"] as? String,
            gender: data["gender"] as? String,
            birthdate: data["birthdate"] as? String,
            thumbPath: data["thumbPath"] as? String,
            originalPath: data["originalPath"] as? String,
            joinedRooms: data["joinedRooms"] as? [String]
        )
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
    
    func checkDuplicate(strToCompare: String, fieldToCompare: String, collectionName: String) async throws -> Bool {
        do {
            let query = db.collection(collectionName).whereField(fieldToCompare, isEqualTo: strToCompare)
            let snapshot = try await query.getDocuments()
            return !snapshot.isEmpty
        } catch {
            throw FirebaseError.Duplicate
        }
    }
    
    func updateLastReadSeq(roomID: String, userID: String, lastReadSeq: Int64) async throws {
        let ref = db.collection("Users").document(userID)
            .collection("roomStates").document(roomID)
        try await ref.setData([
            "lastReadSeq": lastReadSeq,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    func fetchLastReadSeq(for roomID: String) async throws -> Int64 {
        let email = LoginManager.shared.getUserEmail
        let docRef = db.collection("Users").document(email)
            .collection("roomStates").document(roomID)
        
        let snap = try await docRef.getDocument()
        let lastRead = snap.data()?["lastReadSeq"] as? Int64 ?? 0
        return lastRead
    }
}

