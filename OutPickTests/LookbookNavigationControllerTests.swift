import SwiftUI
import Testing
import UIKit
@testable import OutPick

@MainActor
struct LookbookNavigationControllerTests {
    @Test func preventsInteractivePopAtRoot() throws {
        let navigationController = makeNavigationController()
        let gestureRecognizer = try #require(
            navigationController.interactivePopGestureRecognizer
        )

        #expect(navigationController.gestureRecognizerShouldBegin(gestureRecognizer) == false)
        #expect(gestureRecognizer.isEnabled == false)
    }

    @Test func allowsInteractivePopForBrowseController() throws {
        let navigationController = makeNavigationController()
        navigationController.pushViewController(UIViewController(), animated: false)
        let gestureRecognizer = try #require(
            navigationController.interactivePopGestureRecognizer
        )

        #expect(navigationController.gestureRecognizerShouldBegin(gestureRecognizer))
        #expect(gestureRecognizer.isEnabled)
    }

    @Test func updatesEdgeAndContentPopWhenStateChanges() throws {
        let navigationController = makeNavigationController()
        let state = LookbookInteractivePopState(isAllowed: true)
        let hostingController = LookbookHostingController(
            rootView: Text("Stateful"),
            interactivePopState: state
        )
        navigationController.pushViewController(hostingController, animated: false)
        let gestureRecognizer = try #require(
            navigationController.interactivePopGestureRecognizer
        )

        state.setAllowed(false)

        #expect(navigationController.gestureRecognizerShouldBegin(gestureRecognizer) == false)
        #expect(gestureRecognizer.isEnabled == false)
        if #available(iOS 26.0, *) {
            #expect(
                navigationController.interactiveContentPopGestureRecognizer?.isEnabled == false
            )
        }

        state.setAllowed(true)

        #expect(navigationController.gestureRecognizerShouldBegin(gestureRecognizer))
        #expect(gestureRecognizer.isEnabled)
        if #available(iOS 26.0, *) {
            #expect(
                navigationController.interactiveContentPopGestureRecognizer?.isEnabled == true
            )
        }
    }

    private func makeNavigationController() -> LookbookNavigationController {
        let navigationController = LookbookNavigationController(
            rootViewController: UIViewController()
        )
        navigationController.loadViewIfNeeded()
        return navigationController
    }
}
