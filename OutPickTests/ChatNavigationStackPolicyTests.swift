import Testing
@testable import OutPick

struct ChatNavigationStackPolicyTests {
    @Test func placesFirstChatAfterExistingNonChatStack() {
        let action = ChatNavigationStackPolicy.action(
            currentChatRoomIDs: [nil, nil],
            destinationRoomID: "room-a"
        )

        #expect(action == .place(retainedIndices: [0, 1], replacedChatIndices: []))
    }

    @Test func replacesChatAndPreservesNonChatPrefix() {
        let action = ChatNavigationStackPolicy.action(
            currentChatRoomIDs: [nil, nil, "room-a"],
            destinationRoomID: "room-b"
        )

        #expect(action == .place(retainedIndices: [0, 1], replacedChatIndices: [2]))
    }

    @Test func removesEveryPreviousChatWithoutDroppingNonChatRoutes() {
        let action = ChatNavigationStackPolicy.action(
            currentChatRoomIDs: [nil, "room-a", nil, "room-b"],
            destinationRoomID: "room-c"
        )

        #expect(action == .place(retainedIndices: [0, 2], replacedChatIndices: [1, 3]))
    }

    @Test func topSameRoomIsNoOp() {
        let action = ChatNavigationStackPolicy.action(
            currentChatRoomIDs: [nil, "room-a"],
            destinationRoomID: "room-a"
        )

        #expect(action == .noOp)
    }

    @Test func sameRoomBehindNonChatRouteIsReplacedInsteadOfNoOp() {
        let action = ChatNavigationStackPolicy.action(
            currentChatRoomIDs: [nil, "room-a", nil],
            destinationRoomID: "room-a"
        )

        #expect(action == .place(retainedIndices: [0, 2], replacedChatIndices: [1]))
    }

    @Test func closingRoomReturnsToItsOriginatingList() {
        let retainedIndices = ChatNavigationStackPolicy.retainedIndicesAfterClosingRoom(
            sourceIndex: 1,
            isPrecededByRoomCreation: false
        )

        #expect(retainedIndices == [0])
    }

    @Test func closingNewlyCreatedRoomAlsoRemovesCreationRoute() {
        let retainedIndices = ChatNavigationStackPolicy.retainedIndicesAfterClosingRoom(
            sourceIndex: 2,
            isPrecededByRoomCreation: true
        )

        #expect(retainedIndices == [0])
    }

    @Test func closingNestedRoomPreservesEarlierNonChatRoutes() {
        let retainedIndices = ChatNavigationStackPolicy.retainedIndicesAfterClosingRoom(
            sourceIndex: 3,
            isPrecededByRoomCreation: false
        )

        #expect(retainedIndices == [0, 1, 2])
    }

    @Test func closurePresentationBeginsOnlyOnceForSameRoom() {
        var state = ChatRoomClosurePresentationState()

        let firstRoom = state.begin(roomID: "room-a")
        let duplicateRoom = state.begin(roomID: "room-a")
        let secondRoom = state.begin(roomID: "room-b")
        let emptyRoom = state.begin(roomID: "")

        #expect(firstRoom)
        #expect(!duplicateRoom)
        #expect(secondRoom)
        #expect(!emptyRoom)
    }
}
