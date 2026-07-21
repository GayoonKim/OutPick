import Foundation

@MainActor
final class ChatOpenRoomRequestRegistry<StackID: Hashable, Snapshot: Equatable> {
    typealias State = ChatOpenRoomRequestState<StackID, Snapshot>
    typealias Request = State.Request

    struct Acquisition {
        let request: Request
        let task: Task<Void, Error>
    }

    private var state = State()
    private var tasks: [UInt64: Task<Void, Error>] = [:]

    func acquire(
        stackID: StackID,
        roomID: String,
        snapshot: Snapshot,
        makeTask: (Request) -> Task<Void, Error>
    ) -> Acquisition {
        switch state.begin(stackID: stackID, roomID: roomID, snapshot: snapshot) {
        case .join(let request):
            guard let task = tasks[request.token] else {
                state.finish(stackID: stackID, token: request.token)
                return acquire(
                    stackID: stackID,
                    roomID: roomID,
                    snapshot: snapshot,
                    makeTask: makeTask
                )
            }
            return Acquisition(request: request, task: task)

        case .start(let request, let supersededToken):
            if let supersededToken {
                tasks.removeValue(forKey: supersededToken)?.cancel()
            }
            let task = makeTask(request)
            tasks[request.token] = task
            return Acquisition(request: request, task: task)
        }
    }

    func isCurrent(stackID: StackID, token: UInt64, snapshot: Snapshot) -> Bool {
        state.isCurrent(stackID: stackID, token: token, snapshot: snapshot)
    }

    func finish(stackID: StackID, token: UInt64) {
        guard state.finish(stackID: stackID, token: token) else { return }
        tasks[token] = nil
    }
}
