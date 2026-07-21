import Foundation

struct ChatOpenRoomRequestState<StackID: Hashable, Snapshot: Equatable> {
    struct Request: Equatable {
        let token: UInt64
        let roomID: String
        let snapshot: Snapshot
    }

    enum BeginAction: Equatable {
        case start(request: Request, supersededToken: UInt64?)
        case join(request: Request)
    }

    private(set) var requests: [StackID: Request] = [:]
    private var nextToken: UInt64 = 0

    mutating func begin(
        stackID: StackID,
        roomID: String,
        snapshot: Snapshot
    ) -> BeginAction {
        if let current = requests[stackID],
           current.roomID == roomID,
           current.snapshot == snapshot {
            return .join(request: current)
        }

        let supersededToken = requests[stackID]?.token
        nextToken &+= 1
        let request = Request(token: nextToken, roomID: roomID, snapshot: snapshot)
        requests[stackID] = request
        return .start(request: request, supersededToken: supersededToken)
    }

    func isCurrent(
        stackID: StackID,
        token: UInt64,
        snapshot: Snapshot
    ) -> Bool {
        guard let current = requests[stackID] else { return false }
        return current.token == token && current.snapshot == snapshot
    }

    @discardableResult
    mutating func finish(stackID: StackID, token: UInt64) -> Bool {
        guard requests[stackID]?.token == token else { return false }
        requests[stackID] = nil
        return true
    }
}
