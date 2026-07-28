import UIKit

@MainActor
enum MyPageCompositionRoot {
    static func makeRoot(container: MyPageContainer) -> UINavigationController {
        let navigationController = UINavigationController()
        let coordinator = MyPageCoordinator(
            navigationController: navigationController,
            container: container
        )
        navigationController.myPageCoordinator = coordinator
        coordinator.start()
        return navigationController
    }
}

private var myPageCoordinatorAssociationKey: UInt8 = 0

private extension UINavigationController {
    var myPageCoordinator: MyPageCoordinator? {
        get {
            objc_getAssociatedObject(self, &myPageCoordinatorAssociationKey)
                as? MyPageCoordinator
        }
        set {
            objc_setAssociatedObject(
                self,
                &myPageCoordinatorAssociationKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}
