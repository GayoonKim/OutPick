//
//  DefaultMainTabBuilder.swift
//  OutPick
//
//  Created by 김가윤 on 2/3/26.
//

import UIKit

/// 현재(리팩토링 전) 구현을 그대로 감싼 기본 빌더
/// - Note: 기능들이 점진적으로 MVVM + Repository + CompositionRoot로 이동되면
///         이 구현을 기능별 빌더/조립 코드로 대체하면 됩니다.
@MainActor
final class DefaultMainTabBuilder: MainTabBuilding {

    private let lookbookContainer: LookbookContainer
    private let chatCoordinator: ChatCoordinator

    init(lookbookContainer: LookbookContainer, chatContainer: ChatContainer) {
        self.lookbookContainer = lookbookContainer
        self.chatCoordinator = ChatCoordinator(container: chatContainer)
    }

    func makeViewController(for index: Int) -> UIViewController {
        switch index {
        case 0:
            return ChatCompositionRoot.makeRoomListRoot(coordinator: chatCoordinator)

        case 1:
            return ChatCompositionRoot.makeJoinedRoomsRoot(coordinator: chatCoordinator)

        case 2:
            return LookbookCompositionRoot.makeRoot(container: lookbookContainer)

        case 3:
            // 내 설정 탭
            let myPageVC = MyPageViewController()
            let nav = UINavigationController(rootViewController: myPageVC)
            nav.isNavigationBarHidden = true
            return nav

        default:
            return UINavigationController(rootViewController: UIViewController())
        }
    }
}
