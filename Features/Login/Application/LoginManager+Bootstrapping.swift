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
    func bootstrapAfterLogin(userEmail: String, joinedRoomsStore: JoinedRoomsStore) async throws {
        // 0) 세션 이메일 확정
        setUserEmail(userEmail)
        _ = try await ensureUserDocumentID()

        // 1) 프로필 리스너 시작
        userProfileRepository.listenToUserProfile(
            email: self.getUserEmail,
            onCurrentUserProfileUpdated: { profile in
                Task { @MainActor in
                    joinedRoomsStore.replace(with: profile.joinedRooms)
                }
            }
        )

        // 2) 참여 방 선 주입
        //    (AppCoordinator가 loadUserProfile 성공 후 호출하므로 currentUserProfile이 존재하는 것이 정상)
        if let profile = self.currentUserProfile {
            await MainActor.run {
                joinedRoomsStore.replace(with: profile.joinedRooms)
            }
        }

        // 3) 소켓 연결(대기하지 않아도 됨)
        async let _ = SocketIOManager.shared.establishConnection()
    }
}
