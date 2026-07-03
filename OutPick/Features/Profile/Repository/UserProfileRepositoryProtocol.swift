//
//  UserProfileRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import FirebaseFirestore

/// 사용자 프로필 관련 데이터베이스 작업을 위한 프로토콜
protocol UserProfileRepositoryProtocol {
    /// Firebase Auth UID를 canonical user ID로 사용해 users/{canonicalUserID} 문서를 조회/생성
    func resolveOrCreateUserDocumentID(authenticatedUser: AuthenticatedUser) async throws -> String

    /// Firestore에 현재 사용자 프로필 저장
    func saveCurrentUserProfile(
        _ profile: UserProfile,
        userID: String,
        email: String,
        authenticatedUser: AuthenticatedUser?
    ) async throws
    
    /// Firestore에서 현재 로그인 사용자 프로필 조회
    func fetchCurrentUserProfile(userID: String, emailFallback: String) async throws -> UserProfile

    /// Firestore에서 canonical user ID 기반 프로필 조회
    func fetchUserProfile(userID: String) async throws -> UserProfile

    /// 여러 canonical user ID 기반 프로필 일괄 조회
    func fetchUserProfiles(userIDs: [String]) async throws -> [String: UserProfile]
    
    /// 프로필 필드 중복 검사
    func checkDuplicate(strToCompare: String, fieldToCompare: String, collectionName: String) async throws -> Bool
    
    /// 사용자의 방 읽기 상태 업데이트
    func updateLastReadSeq(roomID: String, userUID: String, lastReadSeq: Int64) async throws
    
    /// 사용자의 방 읽기 상태 조회
    func fetchLastReadSeq(for roomID: String, userUID: String) async throws -> Int64

    /// 로그인 기기 식별자 갱신 (users/{id}/meta/session)
    func upsertDeviceID(userDocumentID: String, email: String, deviceID: String) async throws

    /// 로그인 기기 식별자 변경 리스너 시작 (users/{id}/meta/session)
    func listenToDeviceID(
        userDocumentID: String,
        onUpdate: @escaping (String?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration

    /// 현재 로그인 디바이스의 push/presence 상태 갱신 (users/{id}/devices/{deviceID})
    func upsertPushDevice(userDocumentID: String, state: PushDeviceState) async throws
}
