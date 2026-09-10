import Foundation

enum ChatMediaUploadTurnLane: String, Sendable {
    case images
    case video
}

protocol ChatMediaUploadTurnQueueProtocol: Sendable {
    func register(lane: ChatMediaUploadTurnLane, uploadIDs: [String]) async
    func acquire(lane: ChatMediaUploadTurnLane, uploadID: String) async throws
    func release(lane: ChatMediaUploadTurnLane, uploadID: String) async
}

struct ChatMediaUploadTurnQueueSnapshot: Equatable, Sendable {
    let activeUploadIDs: [String]
    let waitingUploadIDs: [String]
    var activeUploadID: String? { activeUploadIDs.first }

    init(activeUploadIDs: [String], waitingUploadIDs: [String]) {
        self.activeUploadIDs = activeUploadIDs
        self.waitingUploadIDs = waitingUploadIDs
    }

    init(activeUploadID: String?, waitingUploadIDs: [String]) {
        self.init(activeUploadIDs: activeUploadID.map { [$0] } ?? [], waitingUploadIDs: waitingUploadIDs)
    }
}

enum ChatMediaUploadTurnError: Error {
    case duplicateRequest
}

actor ChatMediaUploadTurnQueue: ChatMediaUploadTurnQueueProtocol {
    private struct Waiter {
        let uploadID: String
        let continuation: CheckedContinuation<Void, Error>
    }
    private struct LaneState {
        var active: [String] = []
        var order: [String] = []
        var waiters: [Waiter] = []
    }
    private let imageLimit: Int
    private let videoLimit: Int
    private var lanes: [ChatMediaUploadTurnLane: LaneState] = [:]

    init(imageLimit: Int = 1, videoLimit: Int = 1) {
        precondition(imageLimit > 0 && videoLimit > 0)
        self.imageLimit = imageLimit
        self.videoLimit = videoLimit
    }

    func acquire(lane: ChatMediaUploadTurnLane, uploadID: String) async throws {
        if Task.isCancelled {
            cancelWaiting(lane: lane, uploadID: uploadID)
            throw CancellationError()
        }
        let state = lanes[lane] ?? LaneState()
        guard !state.active.contains(uploadID), !state.waiters.contains(where: { $0.uploadID == uploadID }) else {
            throw ChatMediaUploadTurnError.duplicateRequest
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                var state = lanes[lane] ?? LaneState()
                if !state.order.contains(uploadID) { state.order.append(uploadID) }
                state.waiters.append(Waiter(uploadID: uploadID, continuation: continuation))
                lanes[lane] = state
                drain(lane)
            }
        } onCancel: {
            Task { await self.cancelWaiting(lane: lane, uploadID: uploadID) }
        }
        // 대기 해제와 취소가 겹치면 호출자에게 실행권을 넘기기 전에 반환한다.
        if Task.isCancelled {
            release(lane: lane, uploadID: uploadID)
            throw CancellationError()
        }
    }

    func release(lane: ChatMediaUploadTurnLane, uploadID: String) {
        var state = lanes[lane] ?? LaneState()
        state.active.removeAll { $0 == uploadID }
        state.order.removeAll { $0 == uploadID }
        let index = state.waiters.firstIndex { $0.uploadID == uploadID }
        let waiter = index.map { state.waiters.remove(at: $0) }
        lanes[lane] = state
        waiter?.continuation.resume(throwing: CancellationError())
        drain(lane)
    }

    func register(lane: ChatMediaUploadTurnLane, uploadIDs: [String]) async {
        var state = lanes[lane] ?? LaneState()
        for uploadID in uploadIDs where !state.active.contains(uploadID) && !state.order.contains(uploadID) {
            state.order.append(uploadID)
        }
        lanes[lane] = state
    }

    func snapshot(lane: ChatMediaUploadTurnLane) -> ChatMediaUploadTurnQueueSnapshot {
        let state = lanes[lane] ?? LaneState()
        return .init(activeUploadIDs: state.active, waitingUploadIDs: state.order)
    }

    private func drain(_ lane: ChatMediaUploadTurnLane) {
        var state = lanes[lane] ?? LaneState()
        let limit = lane == .images ? imageLimit : videoLimit
        var granted: [Waiter] = []
        while state.active.count < limit, let first = state.order.first,
              let index = state.waiters.firstIndex(where: { $0.uploadID == first }) {
            state.order.removeFirst()
            let waiter = state.waiters.remove(at: index)
            state.active.append(waiter.uploadID)
            granted.append(waiter)
        }
        lanes[lane] = state
        granted.forEach { $0.continuation.resume() }
    }

    private func cancelWaiting(lane: ChatMediaUploadTurnLane, uploadID: String) {
        var state = lanes[lane] ?? LaneState()
        let index = state.waiters.firstIndex(where: { $0.uploadID == uploadID })
        let waiter = index.map { state.waiters.remove(at: $0) }
        state.order.removeAll { $0 == uploadID }
        lanes[lane] = state
        waiter?.continuation.resume(throwing: CancellationError())
        drain(lane)
        // active는 실제 작업 종료 경로에서만 반환한다.
    }
}
