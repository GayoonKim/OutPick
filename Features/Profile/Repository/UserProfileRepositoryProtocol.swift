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
    /// 로그인 identity(provider key) 기준으로 사용자 문서 ID를 조회/생성
    func resolveOrCreateUserDocumentID(authenticatedUser: AuthenticatedUser) async throws -> String

    /// 현재 로그인 사용자 프로필에 대한 실시간 리스너 시작
    func listenToCurrentUserProfile(onCurrentUserProfileUpdated: ((UserProfile) -> Void)?)

    /// 특정 사용자 프로필에 대한 실시간 리스너 시작
    func listenToUserProfile(email: String, onCurrentUserProfileUpdated: ((UserProfile) -> Void)?)
    
    /// 사용자 프로필 변경을 구독할 수 있는 Publisher 반환
    func userProfilePublisher(email: String) -> AnyPublisher<UserProfile, Error>
    
    /// 사용자 프로필 리스너 중지
    func stopListenUserProfile(email: String)
    
    /// Firestore에 사용자 프로필 저장
    func saveCurrentUserProfile() async throws
    
    /// Firestore에서 현재 로그인 사용자 프로필 조회
    func fetchCurrentUserProfile() async throws -> UserProfile

    /// Firestore에서 이메일 기반 프로필 조회(채팅 참여자 표시 등 공개 조회용)
    func fetchUserProfileFromFirestore(email: String) async throws -> UserProfile
    
    /// 여러 사용자 프로필 일괄 조회
    func fetchUserProfiles(emails: [String]) async throws -> [UserProfile]
    
    /// 프로필 필드 중복 검사
    func checkDuplicate(strToCompare: String, fieldToCompare: String, collectionName: String) async throws -> Bool
    
    /// 사용자의 방 읽기 상태 업데이트
    func updateLastReadSeq(roomID: String, userUID: String, lastReadSeq: Int64) async throws
    
    /// 사용자의 방 읽기 상태 조회
    func fetchLastReadSeq(for roomID: String) async throws -> Int64

    /// 로그인 기기 식별자 갱신 (users/{id}/meta/session)
    func upsertDeviceID(deviceID: String) async throws

    /// 로그인 기기 식별자 변경 리스너 시작 (users/{id}/meta/session)
    func listenToDeviceID(
        onUpdate: @escaping (String?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration

    /// 현재 로그인 디바이스의 push/presence 상태 갱신 (users/{id}/devices/{deviceID})
    func upsertPushDevice(userDocumentID: String, state: PushDeviceState) async throws
}

extension UserProfileRepositoryProtocol {
    /// 기존 호출부 호환용 기본 오버로드
    func listenToUserProfile(email: String) {
        listenToUserProfile(email: email, onCurrentUserProfileUpdated: nil)
    }
}
