import Foundation

protocol ChatRealtimeGapRecoveryLoading: Sendable {
    func fetchMessages(
        roomID: String,
        afterSeq: Int64,
        limit: Int
    ) async throws -> [ChatMessage]
}

enum ChatRealtimeGapRecoveryError: Error, Equatable, Sendable {
    case permissionDenied
    case roomNotFound
}

struct UnavailableChatRealtimeGapRecoveryLoader: ChatRealtimeGapRecoveryLoading {
    private struct UnavailableError: Error {}

    func fetchMessages(
        roomID: String,
        afterSeq: Int64,
        limit: Int
    ) async throws -> [ChatMessage] {
        throw UnavailableError()
    }
}

protocol RealtimeOrderingClock: Sendable {
    func sleep(for seconds: TimeInterval) async throws
}

struct LiveRealtimeOrderingClock: RealtimeOrderingClock {
    func sleep(for seconds: TimeInterval) async throws {
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

private enum RealtimeStrictOrderingError: Error {
    case unresolvedGap(expectedSeq: Int64, highestObservedSeq: Int64)
    case sequenceConflict(seq: Int64)
}

actor ChatRoomStrictSessionActor {
    struct Snapshot: Equatable, Sendable {
        let lastReleasedSeq: Int64
        let highestObservedSeq: Int64
        let pendingCount: Int
        let requiresAuthoritativeReload: Bool
        let isDegraded: Bool
        let isSuspended: Bool
        let isTerminal: Bool
    }

    nonisolated let messages: AsyncStream<ChatMessage>

    private let roomID: String
    private let recoveryLoader: ChatRealtimeGapRecoveryLoading
    private let clock: RealtimeOrderingClock
    private let continuation: AsyncStream<ChatMessage>.Continuation
    private let pendingRecoveryThreshold: Int
    private let pendingHardCap: Int
    private let recoveryPageSize: Int
    private let recentReleasedCapacity: Int

    private var lastReleasedSeq: Int64
    private var highestObservedSeq: Int64
    private var pendingBySeq: [Int64: ChatMessage] = [:]
    private var pendingSeqByMessageID: [String: Int64] = [:]
    private var recentReleasedIDs = Set<String>()
    private var recentReleasedOrder: [String] = []
    private var recentReleasedSeqByID: [String: Int64] = [:]
    private var requiresAuthoritativeReload = false
    private var isDegraded = false
    private var hasSequenceConflict = false
    private var isSuspended = false
    private var isTerminal = false
    private var requiresReconnectAudit = false
    private var isFinished = false
    private var graceGeneration: UInt64 = 0
    private var graceTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var recoveryGeneration: UInt64 = 0

    init(
        roomID: String,
        baselineSeq: Int64,
        promotionHighWatermark: Int64,
        recoveryLoader: ChatRealtimeGapRecoveryLoading,
        clock: RealtimeOrderingClock = LiveRealtimeOrderingClock(),
        pendingRecoveryThreshold: Int = 100,
        pendingHardCap: Int = 300,
        recoveryPageSize: Int = 100,
        recentReleasedCapacity: Int = 300
    ) {
        let (stream, continuation) = Self.makeStream()
        self.messages = stream
        self.continuation = continuation
        self.roomID = roomID
        self.lastReleasedSeq = max(0, baselineSeq)
        self.highestObservedSeq = max(baselineSeq, promotionHighWatermark)
        self.recoveryLoader = recoveryLoader
        self.clock = clock
        self.pendingRecoveryThreshold = max(1, pendingRecoveryThreshold)
        self.pendingHardCap = max(1, pendingHardCap)
        self.recoveryPageSize = max(1, recoveryPageSize)
        self.recentReleasedCapacity = max(1, recentReleasedCapacity)
    }

    func start() {
        guard !isSuspended, !hasSequenceConflict else { return }
        isDegraded = false
        guard highestObservedSeq > lastReleasedSeq else { return }
        requestRecoveryImmediately()
    }

    func suspend() {
        guard !isFinished, !isSuspended else { return }
        isSuspended = true
        cancelGraceTimer()
        recoveryGeneration &+= 1
        recoveryTask?.cancel()
        recoveryTask = nil
    }

    func resumeAfterRejoin() {
        guard !isFinished, isSuspended, !hasSequenceConflict else { return }
        isSuspended = false
        isDegraded = false
        requiresReconnectAudit = true
        requestRecoveryImmediately()
    }

    func receive(_ message: ChatMessage) {
        guard !isFinished, message.roomID == roomID else { return }
        guard message.seq > 0 else {
            continuation.yield(message)
            return
        }

        guard !isSuspended, !hasSequenceConflict else { return }
        // 이전 recovery cycle이 모두 실패했더라도 새 ingress는 D11의 새 cycle trigger다.
        isDegraded = false
        ingest(message, source: .socket)
        evaluateGapAfterIngress()
    }

    func publishLocal(_ message: ChatMessage) {
        guard !isFinished, message.roomID == roomID else { return }
        continuation.yield(message)
    }

    func currentLastReleasedSeq() -> Int64 {
        lastReleasedSeq
    }

    func snapshot() -> Snapshot {
        Snapshot(
            lastReleasedSeq: lastReleasedSeq,
            highestObservedSeq: highestObservedSeq,
            pendingCount: pendingBySeq.count,
            requiresAuthoritativeReload: requiresAuthoritativeReload,
            isDegraded: isDegraded,
            isSuspended: isSuspended,
            isTerminal: isTerminal
        )
    }

    func finish() {
        isFinished = true
        graceTask?.cancel()
        graceTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        recoveryGeneration &+= 1
        pendingBySeq.removeAll(keepingCapacity: false)
        pendingSeqByMessageID.removeAll(keepingCapacity: false)
        recentReleasedIDs.removeAll(keepingCapacity: false)
        recentReleasedOrder.removeAll(keepingCapacity: false)
        recentReleasedSeqByID.removeAll(keepingCapacity: false)
        continuation.finish()
    }

    private enum IngressSource {
        case socket
        case recovery
    }

    private func ingest(_ message: ChatMessage, source: IngressSource) {
        guard !isFinished, !isSuspended, !hasSequenceConflict else { return }
        highestObservedSeq = max(highestObservedSeq, message.seq)

        if let releasedSeq = recentReleasedSeqByID[message.ID] {
            if releasedSeq != message.seq {
                enterDegradedState(for: message.seq)
            }
            return
        }
        guard message.seq > lastReleasedSeq else { return }

        if let pendingSeq = pendingSeqByMessageID[message.ID] {
            if pendingSeq != message.seq {
                enterDegradedState(for: message.seq)
            }
            return
        }
        if let existing = pendingBySeq[message.seq] {
            if existing.ID != message.ID {
                enterDegradedState(for: message.seq)
            }
            return
        }

        if message.seq == lastReleasedSeq + 1 {
            release(message)
            flushContiguousPending()
            return
        }

        if pendingBySeq.count < pendingHardCap {
            pendingBySeq[message.seq] = message
            pendingSeqByMessageID[message.ID] = message.seq
        } else {
            requiresAuthoritativeReload = true
            if source == .recovery {
                enterDegradedState(for: message.seq)
            }
        }
    }

    private func release(_ message: ChatMessage) {
        lastReleasedSeq = message.seq
        rememberReleased(message)
        continuation.yield(message)
    }

    private func flushContiguousPending() {
        while let next = pendingBySeq[lastReleasedSeq + 1] {
            pendingBySeq.removeValue(forKey: next.seq)
            pendingSeqByMessageID.removeValue(forKey: next.ID)
            release(next)
        }

        if lastReleasedSeq >= highestObservedSeq {
            requiresAuthoritativeReload = false
            cancelGraceTimer()
        }
    }

    private func rememberReleased(_ message: ChatMessage) {
        guard recentReleasedIDs.insert(message.ID).inserted else { return }
        recentReleasedOrder.append(message.ID)
        recentReleasedSeqByID[message.ID] = message.seq
        if recentReleasedOrder.count > recentReleasedCapacity {
            let oldestID = recentReleasedOrder.removeFirst()
            recentReleasedIDs.remove(oldestID)
            recentReleasedSeqByID.removeValue(forKey: oldestID)
        }
    }

    private func evaluateGapAfterIngress() {
        guard !isFinished, !isSuspended, !hasSequenceConflict else { return }
        guard lastReleasedSeq < highestObservedSeq else {
            cancelGraceTimer()
            return
        }

        if requiresAuthoritativeReload || pendingBySeq.count >= pendingRecoveryThreshold {
            requestRecoveryImmediately()
        } else {
            scheduleGraceTimerIfNeeded()
        }
    }

    private func scheduleGraceTimerIfNeeded() {
        guard graceTask == nil, recoveryTask == nil else { return }
        graceGeneration &+= 1
        let generation = graceGeneration
        let clock = clock
        graceTask = Task { [weak self] in
            do {
                try await clock.sleep(for: 0.5)
                await self?.graceExpired(generation: generation)
            } catch {
                // 취소는 정상적인 상태 전이이다.
            }
        }
    }

    private func graceExpired(generation: UInt64) {
        guard !isFinished, generation == graceGeneration else { return }
        graceTask = nil
        guard lastReleasedSeq < highestObservedSeq else { return }
        requestRecoveryImmediately()
    }

    private func cancelGraceTimer() {
        graceGeneration &+= 1
        graceTask?.cancel()
        graceTask = nil
    }

    private func requestRecoveryImmediately() {
        guard !isFinished, !isSuspended, !hasSequenceConflict, recoveryTask == nil else { return }
        cancelGraceTimer()
        recoveryGeneration &+= 1
        let generation = recoveryGeneration
        recoveryTask = Task { [weak self] in
            await self?.runRecoveryCycle(generation: generation)
        }
    }

    private func runRecoveryCycle(generation: UInt64) async {
        defer {
            if recoveryGeneration == generation {
                recoveryTask = nil
            }
        }

        for attempt in 1...3 {
            guard !Task.isCancelled,
                  !isFinished,
                  !isSuspended,
                  recoveryGeneration == generation else { return }
            do {
                try await recoverUntilHighWatermark(generation: generation)
                return
            } catch {
                if let terminalError = error as? ChatRealtimeGapRecoveryError {
                    terminate(for: terminalError)
                    return
                }
                guard attempt < 3 else {
                    isDegraded = true
                    #if DEBUG
                    print(
                        "[ChatRoomStrictSessionActor] recovery degraded " +
                        "roomID=\(roomID) expectedSeq=\(lastReleasedSeq + 1) " +
                        "highestObservedSeq=\(highestObservedSeq) error=\(error)"
                    )
                    #endif
                    return
                }

                do {
                    try await clock.sleep(for: attempt == 1 ? 0.5 : 1.0)
                } catch {
                    return
                }
            }
        }
    }

    private func recoverUntilHighWatermark(generation: UInt64) async throws {
        while lastReleasedSeq < highestObservedSeq || requiresReconnectAudit {
            let beforeFetchSeq = lastReleasedSeq
            let isReconnectAuditPage = requiresReconnectAudit
            let page = try await recoveryLoader.fetchMessages(
                roomID: roomID,
                afterSeq: beforeFetchSeq,
                limit: recoveryPageSize
            )
            guard !Task.isCancelled,
                  !isSuspended,
                  recoveryGeneration == generation else {
                throw CancellationError()
            }
            guard !page.isEmpty else {
                if isReconnectAuditPage, lastReleasedSeq >= highestObservedSeq {
                    requiresReconnectAudit = false
                    break
                }
                throw RealtimeStrictOrderingError.unresolvedGap(
                    expectedSeq: lastReleasedSeq + 1,
                    highestObservedSeq: highestObservedSeq
                )
            }

            for message in page.sorted(by: Self.messageOrder) {
                guard message.roomID == roomID, message.seq > beforeFetchSeq else { continue }
                ingest(message, source: .recovery)
                if isDegraded {
                    throw RealtimeStrictOrderingError.sequenceConflict(seq: message.seq)
                }
            }

            guard lastReleasedSeq > beforeFetchSeq else {
                throw RealtimeStrictOrderingError.unresolvedGap(
                    expectedSeq: lastReleasedSeq + 1,
                    highestObservedSeq: highestObservedSeq
                )
            }

            if isReconnectAuditPage, page.count < recoveryPageSize {
                requiresReconnectAudit = false
            }

            if !requiresReconnectAudit,
               page.count < recoveryPageSize,
               lastReleasedSeq < highestObservedSeq {
                throw RealtimeStrictOrderingError.unresolvedGap(
                    expectedSeq: lastReleasedSeq + 1,
                    highestObservedSeq: highestObservedSeq
                )
            }
        }

        requiresAuthoritativeReload = false
        isDegraded = false
    }

    private func enterDegradedState(for seq: Int64) {
        hasSequenceConflict = true
        isDegraded = true
        cancelGraceTimer()
        #if DEBUG
        print(
            "[ChatRoomStrictSessionActor] sequence conflict " +
            "roomID=\(roomID) seq=\(seq)"
        )
        #endif
    }

    private func terminate(for error: ChatRealtimeGapRecoveryError) {
        guard !isFinished else { return }
        isTerminal = true
        isDegraded = true
        isFinished = true
        cancelGraceTimer()
        pendingBySeq.removeAll(keepingCapacity: false)
        pendingSeqByMessageID.removeAll(keepingCapacity: false)
        continuation.finish()
        #if DEBUG
        print("[ChatRoomStrictSessionActor] terminal recovery roomID=\(roomID) error=\(error)")
        #endif
    }

    nonisolated private static func messageOrder(
        _ lhs: ChatMessage,
        _ rhs: ChatMessage
    ) -> Bool {
        if lhs.seq != rhs.seq { return lhs.seq < rhs.seq }
        return lhs.ID < rhs.ID
    }

    nonisolated private static func makeStream()
        -> (AsyncStream<ChatMessage>, AsyncStream<ChatMessage>.Continuation) {
        var continuation: AsyncStream<ChatMessage>.Continuation!
        let stream = AsyncStream<ChatMessage> { continuation = $0 }
        return (stream, continuation)
    }
}
