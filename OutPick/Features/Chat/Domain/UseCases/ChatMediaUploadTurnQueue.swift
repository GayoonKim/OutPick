import Foundation

enum ChatMediaUploadTurnLane: String, Sendable {
    case images
    case video
}

protocol ChatMediaUploadTurnQueueProtocol: Sendable {
    func acquire(lane: ChatMediaUploadTurnLane, uploadID: String) async throws
    func release(lane: ChatMediaUploadTurnLane, uploadID: String) async
}

struct ChatMediaUploadTurnQueueSnapshot: Equatable, Sendable {
    let activeUploadID: String?
    let waitingUploadIDs: [String]
}

actor ChatMediaUploadTurnQueue: ChatMediaUploadTurnQueueProtocol {
    private struct Waiter {
        let uploadID: String
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct LaneState {
        var activeUploadID: String?
        var waiters: [Waiter] = []
        var canceledUploadIDs: Set<String> = []
    }

    private var lanes: [ChatMediaUploadTurnLane: LaneState] = [:]

    func acquire(lane: ChatMediaUploadTurnLane, uploadID: String) async throws {
        try Task.checkCancellation()
        var state = lanes[lane] ?? LaneState()
        if state.activeUploadID == nil {
            state.activeUploadID = uploadID
            lanes[lane] = state
            return
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enqueue(
                    lane: lane,
                    uploadID: uploadID,
                    continuation: continuation
                )
            }
        } onCancel: {
            Task { await self.cancelWaiting(lane: lane, uploadID: uploadID) }
        }
    }

    func release(lane: ChatMediaUploadTurnLane, uploadID: String) async {
        var state = lanes[lane] ?? LaneState()
        guard state.activeUploadID == uploadID else {
            state.waiters.removeAll { $0.uploadID == uploadID }
            lanes[lane] = state
            return
        }

        state.activeUploadID = nil
        while !state.waiters.isEmpty {
            let next = state.waiters.removeFirst()
            if state.canceledUploadIDs.remove(next.uploadID) != nil {
                next.continuation.resume(throwing: CancellationError())
                continue
            }
            state.activeUploadID = next.uploadID
            lanes[lane] = state
            next.continuation.resume()
            return
        }
        lanes[lane] = state
    }

    func snapshot(lane: ChatMediaUploadTurnLane) -> ChatMediaUploadTurnQueueSnapshot {
        let state = lanes[lane] ?? LaneState()
        return ChatMediaUploadTurnQueueSnapshot(
            activeUploadID: state.activeUploadID,
            waitingUploadIDs: state.waiters.map(\.uploadID)
        )
    }

    private func enqueue(
        lane: ChatMediaUploadTurnLane,
        uploadID: String,
        continuation: CheckedContinuation<Void, Error>
    ) {
        var state = lanes[lane] ?? LaneState()
        if state.canceledUploadIDs.remove(uploadID) != nil {
            lanes[lane] = state
            continuation.resume(throwing: CancellationError())
            return
        }
        state.waiters.append(Waiter(uploadID: uploadID, continuation: continuation))
        lanes[lane] = state
    }

    private func cancelWaiting(lane: ChatMediaUploadTurnLane, uploadID: String) async {
        var state = lanes[lane] ?? LaneState()
        if state.activeUploadID == uploadID {
            await release(lane: lane, uploadID: uploadID)
            return
        }
        if let index = state.waiters.firstIndex(where: { $0.uploadID == uploadID }) {
            let waiter = state.waiters.remove(at: index)
            lanes[lane] = state
            waiter.continuation.resume(throwing: CancellationError())
            return
        }
        state.canceledUploadIDs.insert(uploadID)
        lanes[lane] = state
    }
}
