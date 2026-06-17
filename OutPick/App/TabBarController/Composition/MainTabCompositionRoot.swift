//
//  MainTabCompositionRoot.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit

/// 메인 탭(CustomTabBarViewController)을 조립하는 루트
/// - Note: AppCoordinator는 여기서 만든 VC를 root로 세팅만 하고, 내부 조립을 몰라도 됩니다.
@MainActor
enum MainTabCompositionRoot {

    static func makeMainTab(lookbookContainer: LookbookContainer, chatContainer: ChatContainer) -> CustomTabBarViewController {
        let vc = CustomTabBarViewController()

        lookbookContainer.configureLookbookChatShare(
            loadShareableJoinedRoomsUseCase: chatContainer.makeLoadShareableJoinedRoomsUseCase(),
            shareLookbookContentToChatUseCase: chatContainer.makeShareLookbookContentToChatUseCase(),
            roomImageManager: chatContainer.provider.roomImageManager
        )

        // 탭 생성 책임은 빌더로 위임
        let tabBuilder = DefaultMainTabBuilder(lookbookContainer: lookbookContainer, chatContainer: chatContainer)
        vc.tabBuilder = tabBuilder

        let appContentRouter = DefaultAppContentRouter(
            tabController: vc,
            lookbookContainer: lookbookContainer,
            tabBuilder: tabBuilder
        )
        tabBuilder.appContentRouter = appContentRouter
        lookbookContainer.configureAppContentRouter(appContentRouter)

        return vc
    }
}
