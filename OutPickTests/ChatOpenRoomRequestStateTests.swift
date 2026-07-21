import Testing
@testable import OutPick

struct ChatOpenRoomRequestStateTests {
    @Test func sameStackRoomAndSnapshotJoinCurrentRequest() {
        var state = ChatOpenRoomRequestState<String, [String]>()
        let first = state.begin(stackID: "joined", roomID: "room-a", snapshot: ["root"])
        let second = state.begin(stackID: "joined", roomID: "room-a", snapshot: ["root"])

        guard case .start(let firstRequest, nil) = first,
              case .join(let joinedRequest) = second else {
            Issue.record("같은 stack·room 요청이 join되지 않았습니다.")
            return
        }

        #expect(firstRequest == joinedRequest)
    }

    @Test func differentRoomInSameStackSupersedesCurrentRequest() {
        var state = ChatOpenRoomRequestState<String, [String]>()
        let first = state.begin(stackID: "joined", roomID: "room-a", snapshot: ["root"])
        let second = state.begin(stackID: "joined", roomID: "room-b", snapshot: ["root"])

        guard case .start(let firstRequest, nil) = first,
              case .start(let secondRequest, let supersededToken) = second else {
            Issue.record("다른 room 요청이 새 owner가 되지 않았습니다.")
            return
        }

        #expect(supersededToken == firstRequest.token)
        #expect(secondRequest.token != firstRequest.token)
        #expect(state.isCurrent(stackID: "joined", token: secondRequest.token, snapshot: ["root"]))
    }

    @Test func changedSnapshotStartsNewRequestEvenForSameRoom() {
        var state = ChatOpenRoomRequestState<String, [String]>()
        let first = state.begin(stackID: "joined", roomID: "room-a", snapshot: ["root"])
        let second = state.begin(stackID: "joined", roomID: "room-a", snapshot: ["root", "search"])

        guard case .start(let firstRequest, nil) = first,
              case .start(let secondRequest, let supersededToken) = second else {
            Issue.record("변경된 stack snapshot이 새 요청을 만들지 않았습니다.")
            return
        }

        #expect(supersededToken == firstRequest.token)
        #expect(secondRequest.snapshot == ["root", "search"])
    }

    @Test func differentStacksKeepIndependentCurrentRequests() {
        var state = ChatOpenRoomRequestState<String, [String]>()
        let joined = state.begin(stackID: "joined", roomID: "room-a", snapshot: ["joined-root"])
        let open = state.begin(stackID: "open", roomID: "room-c", snapshot: ["open-root"])

        guard case .start(let joinedRequest, nil) = joined,
              case .start(let openRequest, nil) = open else {
            Issue.record("서로 다른 stack 요청이 독립적으로 시작되지 않았습니다.")
            return
        }

        #expect(state.isCurrent(stackID: "joined", token: joinedRequest.token, snapshot: ["joined-root"]))
        #expect(state.isCurrent(stackID: "open", token: openRequest.token, snapshot: ["open-root"]))
    }

    @Test func changedCurrentSnapshotMakesCompletionStale() {
        var state = ChatOpenRoomRequestState<String, [String]>()
        let action = state.begin(stackID: "joined", roomID: "room-a", snapshot: ["root"])

        guard case .start(let request, nil) = action else {
            Issue.record("요청이 시작되지 않았습니다.")
            return
        }

        #expect(!state.isCurrent(stackID: "joined", token: request.token, snapshot: ["root", "room-b"]))
    }

    @Test func staleFinishCannotRemoveNewerRequest() {
        var state = ChatOpenRoomRequestState<String, [String]>()
        let first = state.begin(stackID: "joined", roomID: "room-a", snapshot: ["root"])
        let second = state.begin(stackID: "joined", roomID: "room-b", snapshot: ["root"])

        guard case .start(let firstRequest, nil) = first,
              case .start(let secondRequest, _) = second else {
            Issue.record("요청 준비에 실패했습니다.")
            return
        }

        let didFinishStaleRequest = state.finish(stackID: "joined", token: firstRequest.token)
        #expect(!didFinishStaleRequest)
        #expect(state.isCurrent(stackID: "joined", token: secondRequest.token, snapshot: ["root"]))
        let didFinishCurrentRequest = state.finish(stackID: "joined", token: secondRequest.token)
        #expect(didFinishCurrentRequest)
    }
}
