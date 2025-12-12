//
//  UserProfileRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import Combine
import FirebaseFirestore

/// 사용자 프로필 관련 데이터베이스 작업을 위한 프로토콜
protocol UserProfileRepositoryProtocol {
    /// 특정 사용자 프로필에 대한 실시간 리스너 시작
    func listenToUserProfile(email: String)
    
    /// 사용자 프로필 변경을 구독할 수 있는 Publisher 반환
    func userProfilePublisher(email: String) -> AnyPublisher<UserProfile, Error>
    
    /// 사용자 프로필 리스너 중지
    func stopListenUserProfile(email: String)
    
    /// Firestore에 사용자 프로필 저장
    func saveUserProfileToFirestore(email: String) async throws
    
    /// Firestore에서 사용자 프로필 조회
    func fetchUserProfileFromFirestore(email: String) async throws -> UserProfile
    
    /// 여러 사용자 프로필 일괄 조회
    func fetchUserProfiles(emails: [String]) async throws -> [UserProfile]
    
    /// 프로필 필드 중복 검사
    func checkDuplicate(strToCompare: String, fieldToCompare: String, collectionName: String) async throws -> Bool
    
    /// 사용자의 방 읽기 상태 업데이트
    func updateLastReadSeq(roomID: String, userID: String, lastReadSeq: Int64) async throws
    
    /// 사용자의 방 읽기 상태 조회
    func fetchLastReadSeq(for roomID: String) async throws -> Int64
}

