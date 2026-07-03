//
//  LoginManager+Bootstrapping.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit

extension LoginManager: LoginBootstrappingProtocol {

    /// 초기화만 담당
    /// 호출 위치: AppCoordinator에서 Main(Tab) 라우팅 직후
    func bootstrapAfterLogin(
        currentUserProfile: UserProfile,
        joinedRoomsStore: JoinedRoomsSessionStoring,
        joinedRoomsRuntime: JoinedRoomsSessionRuntimeHandling,
        brandAdminSessionStore: BrandAdminSessionStore
    ) async throws {
        // 0) 세션 사용자 문서 확정
        _ = try await ensureUserDocumentID()

        // 1) 참여 방 선 주입
        let joinedRoomIDs = try await FirebaseRepositoryProvider.shared.chatRoomRepository
            .fetchJoinedRoomList(userUID: canonicalUserID)
            .map(\.roomID)

        await MainActor.run {
            joinedRoomsStore.replace(with: joinedRoomIDs)
            joinedRoomsRuntime.replaceJoinedRooms(Set(joinedRoomIDs))
        }

        // 2) 브랜드 권한 선로딩
        await brandAdminSessionStore.refreshCurrentSession(force: true)
        await brandAdminSessionStore.refreshWritableBrands(force: true)

        // 3) 소켓 연결은 AppSessionRuntime이 인증 세션 시작 시 담당한다.
    }
}
