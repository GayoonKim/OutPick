import Foundation

struct ChatRoomRouteLifecycleState: Equatable {
    private(set) var isNavigationOwned = false
    private(set) var isDismissalCandidate = false
    private(set) var isFinished = false
    var canRestoreTransientState: Bool { !isFinished }

    mutating func didAppear(isNavigationOwned: Bool) {
        self.isNavigationOwned = isNavigationOwned
        isDismissalCandidate = false
    }

    mutating func willDisappear(isMovingFromParent: Bool, isBeingDismissed: Bool) {
        isDismissalCandidate = isMovingFromParent || isBeingDismissed
    }

    mutating func shouldFinishAfterDisappearance(isStillInNavigationStack: Bool) -> Bool {
        guard !isFinished else { return false }

        let didLeaveNavigationRoute = isNavigationOwned && !isStillInNavigationStack
        let didDismissModalRoute = !isNavigationOwned && isDismissalCandidate
        guard didLeaveNavigationRoute || didDismissModalRoute else { return false }

        isFinished = true
        return true
    }

    mutating func finishForReplacement() -> Bool {
        guard !isFinished else { return false }
        isFinished = true
        return true
    }
}
