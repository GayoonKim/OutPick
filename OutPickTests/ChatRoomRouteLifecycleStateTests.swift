import Testing
@testable import OutPick

struct ChatRoomRouteLifecycleStateTests {
    @Test func transientCoverDoesNotFinishNavigationRoute() {
        var state = ChatRoomRouteLifecycleState()
        state.didAppear(isNavigationOwned: true)
        state.willDisappear(isMovingFromParent: false, isBeingDismissed: false)

        let shouldFinish = state.shouldFinishAfterDisappearance(
            isStillInNavigationStack: true
        )

        #expect(!shouldFinish)
        #expect(!state.isFinished)
    }

    @Test func completedNavigationPopFinishesRoute() {
        var state = ChatRoomRouteLifecycleState()
        state.didAppear(isNavigationOwned: true)
        state.willDisappear(isMovingFromParent: true, isBeingDismissed: false)

        let shouldFinish = state.shouldFinishAfterDisappearance(
            isStillInNavigationStack: false
        )

        #expect(shouldFinish)
        #expect(state.isFinished)
    }

    @Test func cancelledInteractivePopKeepsRoute() {
        var state = ChatRoomRouteLifecycleState()
        state.didAppear(isNavigationOwned: true)
        state.willDisappear(isMovingFromParent: true, isBeingDismissed: false)

        let shouldFinish = state.shouldFinishAfterDisappearance(
            isStillInNavigationStack: true
        )

        #expect(!shouldFinish)
        #expect(!state.isFinished)
    }

    @Test func modalDismissalAndReplacementFinishOnlyOnce() {
        var modalState = ChatRoomRouteLifecycleState()
        modalState.didAppear(isNavigationOwned: false)
        modalState.willDisappear(isMovingFromParent: false, isBeingDismissed: true)

        let firstModalFinish = modalState.shouldFinishAfterDisappearance(
            isStillInNavigationStack: false
        )
        let secondModalFinish = modalState.shouldFinishAfterDisappearance(
            isStillInNavigationStack: false
        )
        #expect(firstModalFinish)
        #expect(!secondModalFinish)

        var replacementState = ChatRoomRouteLifecycleState()
        replacementState.didAppear(isNavigationOwned: true)
        let firstReplacementFinish = replacementState.finishForReplacement()
        let secondReplacementFinish = replacementState.finishForReplacement()
        #expect(firstReplacementFinish)
        #expect(!secondReplacementFinish)
    }
}
