import SwiftUI
import UIKit

@MainActor
protocol LookbookInteractivePopControlling: AnyObject {
    var allowsLookbookInteractivePop: Bool { get }
}

enum LookbookInteractivePopPolicy {
    case browse
    case stateful
    case blocked

    var initiallyAllowsPop: Bool {
        switch self {
        case .browse, .stateful:
            return true
        case .blocked:
            return false
        }
    }
}

@MainActor
final class LookbookNavigationController: UINavigationController,
    UIGestureRecognizerDelegate,
    UINavigationControllerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self
        interactivePopGestureRecognizer?.delegate = self
        refreshInteractivePopAvailability()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === interactivePopGestureRecognizer else { return true }
        guard viewControllers.count > 1, transitionCoordinator == nil else { return false }
        return topViewControllerAllowsInteractivePop
    }

    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        refreshInteractivePopAvailability()
    }

    func refreshInteractivePopAvailability() {
        let isAvailable = viewControllers.count > 1 && topViewControllerAllowsInteractivePop
        interactivePopGestureRecognizer?.isEnabled = isAvailable

        if #available(iOS 26.0, *) {
            interactiveContentPopGestureRecognizer?.isEnabled = isAvailable
        }
    }

    private var topViewControllerAllowsInteractivePop: Bool {
        guard let controller = topViewController as? LookbookInteractivePopControlling else {
            return true
        }
        return controller.allowsLookbookInteractivePop
    }
}

@MainActor
final class LookbookHostingController<Content: View>: UIHostingController<Content>,
    LookbookInteractivePopControlling {

    private let interactivePopState: LookbookInteractivePopState

    var allowsLookbookInteractivePop: Bool {
        interactivePopState.isAllowed
    }

    init(
        rootView: Content,
        interactivePopState: LookbookInteractivePopState
    ) {
        self.interactivePopState = interactivePopState
        super.init(rootView: rootView)

        interactivePopState.onChange = { [weak self] in
            guard let self,
                  self.navigationController?.topViewController === self else { return }
            (self.navigationController as? LookbookNavigationController)?
                .refreshInteractivePopAvailability()
        }
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
