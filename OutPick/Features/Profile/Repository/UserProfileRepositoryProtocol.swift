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
    /// Firebase Auth UID를 canonical user ID로 확정한다. Firestore 문서는 생성하지 않는다.
    func resolveOrCreateUserDocumentID(authenticatedUser: AuthenticatedUser) async throws -> String

    /// 사용자의 방 읽기 상태 업데이트
    func updateLastReadSeq(roomID: String, userUID: String, lastReadSeq: Int64) async throws
    
    /// 사용자의 방 읽기 상태 조회
    func fetchLastReadSeq(for roomID: String, userUID: String) async throws -> Int64

    /// 진단용 서버 권위 읽기 상태 조회
    func fetchAuthoritativeLastReadSeq(for roomID: String, userUID: String) async throws -> Int64

    /// 로그인 기기 식별자 갱신 (`users/{id}/meta/session`)
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

extension UserProfileRepositoryProtocol {
    func fetchAuthoritativeLastReadSeq(for roomID: String, userUID: String) async throws -> Int64 {
        try await fetchLastReadSeq(for: roomID, userUID: userUID)
    }
}
