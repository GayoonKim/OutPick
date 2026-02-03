//
//  LoginManager+Bootstrapping.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit

extension LoginManager: LoginBootstrappingProtocol {

    /// ✅ 초기화만 담당 (화면 생성/라우팅 X)
    /// - 호출 위치: AppCoordinator에서 Main(Tab) 라우팅 직후
    func bootstrapAfterLogin(userEmail: String) async throws {
        // 0) 세션 이메일 확정
        setUserEmail(userEmail)

        // 1) 프로필 리스너 시작
        FirebaseManager.shared.listenToUserProfile(email: self.getUserEmail)

        // 2) 참여 방 선 주입
        //    (AppCoordinator가 loadUserProfile 성공 후 호출하므로 currentUserProfile이 존재하는 것이 정상)
        if let profile = self.currentUserProfile {
            await FirebaseManager.shared.joinedRoomStore.replace(with: profile.joinedRooms)
        }

        // 3) 홈 데이터 프리페치/초기화
        try await FirebaseManager.shared.fetchTopRoomsPage(limit: 30)

        // 4) 소켓 연결(대기하지 않아도 됨)
        async let _ = SocketIOManager.shared.establishConnection()

        // 5) 기존 유저(=프로필 존재) 기준 초기화
        let joinedRooms = self.currentUserProfile?.joinedRooms ?? []
        if joinedRooms.isEmpty == false {
            BannerManager.shared.start(for: joinedRooms)

            Task.detached {
                await FirebaseManager.shared.startListenRoomDocs(roomIDs: joinedRooms)
            }

            for roomID in joinedRooms {
                SocketIOManager.shared.joinRoom(roomID)
            }
        }
    }
}
