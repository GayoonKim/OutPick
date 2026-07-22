import Testing
import UIKit
@testable import OutPick

@MainActor
struct ChatNavigationControllerTests {
    @Test func preventsInteractivePopAtRoot() throws {
        let navigationController = makeNavigationController()
        let gestureRecognizer = try #require(navigationController.interactivePopGestureRecognizer)

        #expect(navigationController.gestureRecognizerShouldBegin(gestureRecognizer) == false)
    }

    @Test func allowsInteractivePopAfterPush() throws {
        let navigationController = makeNavigationController()
        navigationController.pushViewController(UIViewController(), animated: false)
        let gestureRecognizer = try #require(navigationController.interactivePopGestureRecognizer)

        #expect(navigationController.gestureRecognizerShouldBegin(gestureRecognizer))
    }

    @Test func preventsInteractivePopWhenTopViewControllerDisallowsIt() throws {
        let navigationController = makeNavigationController()
        navigationController.pushViewController(
            InteractivePopBlockingViewController(),
            animated: false
        )
        let gestureRecognizer = try #require(navigationController.interactivePopGestureRecognizer)

        #expect(navigationController.gestureRecognizerShouldBegin(gestureRecognizer) == false)
    }

    @Test func keepsIOS26ContentPopEnabled() {
        let navigationController = makeNavigationController()

        if #available(iOS 26.0, *) {
            #expect(navigationController.interactiveContentPopGestureRecognizer?.isEnabled == true)
        }
    }

    private func makeNavigationController() -> ChatNavigationController {
        let navigationController = ChatNavigationController(
            rootViewController: UIViewController()
        )
        navigationController.loadViewIfNeeded()
        return navigationController
    }
}

@MainActor
private final class InteractivePopBlockingViewController: UIViewController, ChatInteractivePopControlling {
    var allowsChatInteractivePop: Bool { false }
}
