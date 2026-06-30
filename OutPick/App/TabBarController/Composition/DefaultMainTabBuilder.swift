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
    var appContentRouter: (any AppContentRouting)? {
        didSet {
            chatCoordinator.appContentRouter = appContentRouter
        }
    }

    init(lookbookContainer: LookbookContainer, chatContainer: ChatContainer) {
        self.lookbookContainer = lookbookContainer
        self.chatCoordinator = ChatCoordinator(container: chatContainer)
    }

    func makeTabViewControllers() -> [UIViewController] {
        (0..<5).map { index in
            let viewController = makeViewController(for: index)
            configureTabItem(for: viewController, index: index)
            configureNavigationControllerIfNeeded(viewController)
            return viewController
        }
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
            return LookbookCompositionRoot.makeLikedRoot(container: lookbookContainer)

        case 4:
            // 내 설정 탭
            let myPageVC = MyPageViewController()
            let nav = UINavigationController(rootViewController: myPageVC)
            nav.isNavigationBarHidden = true
            return nav

        default:
            return UINavigationController(rootViewController: UIViewController())
        }
    }

    func openChatRoom(roomID: String, from source: UIViewController) async throws {
        try await chatCoordinator.openRoom(roomID: roomID, from: source)
    }

    private func configureTabItem(for viewController: UIViewController, index: Int) {
        let item: UITabBarItem
        switch index {
        case 0:
            item = UITabBarItem(
                title: "오픈채팅",
                image: UIImage(systemName: "bubble.left.and.bubble.right.fill"),
                selectedImage: UIImage(systemName: "bubble.left.and.bubble.right.fill")
            )

        case 1:
            item = UITabBarItem(
                title: "채팅",
                image: UIImage(systemName: "bubble.middle.bottom.fill"),
                selectedImage: UIImage(systemName: "bubble.middle.bottom.fill")
            )

        case 2:
            item = UITabBarItem(
                title: "룩북",
                image: UIImage(systemName: "book.fill"),
                selectedImage: UIImage(systemName: "book.fill")
            )

        case 3:
            item = UITabBarItem(
                title: "좋아요",
                image: UIImage(systemName: "heart.fill"),
                selectedImage: UIImage(systemName: "heart.fill")
            )

        case 4:
            item = UITabBarItem(
                title: "내 정보",
                image: UIImage(systemName: "gearshape.fill"),
                selectedImage: UIImage(systemName: "gearshape.fill")
            )

        default:
            item = UITabBarItem()
        }

        viewController.tabBarItem = item
    }

    private func configureNavigationControllerIfNeeded(_ viewController: UIViewController) {
        guard let nav = viewController as? UINavigationController else { return }
        nav.isNavigationBarHidden = true
        nav.setNavigationBarHidden(true, animated: false)
        nav.interactivePopGestureRecognizer?.isEnabled = true
    }
}
