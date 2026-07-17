import Foundation
import Testing
@testable import OutPick

struct SocketSessionIdentityTests {
    @Test
    func replacingIDTokenPreservesSessionContractAndUpdatesHandshakeCredentials() throws {
        let identity = SocketSessionIdentity(
            uid: "uid-1",
            email: "user@example.com",
            nickname: "사용자",
            avatarPath: "avatars/user.jpg",
            clientKey: "ios-device",
            socketURL: try #require(URL(string: "https://socket.example.com")),
            idToken: "expired-token"
        )

        let refreshed = try identity.replacingIDToken("  fresh-token  ")

        #expect(refreshed.uid == identity.uid)
        #expect(refreshed.email == identity.email)
        #expect(refreshed.nickname == identity.nickname)
        #expect(refreshed.avatarPath == identity.avatarPath)
        #expect(refreshed.clientKey == identity.clientKey)
        #expect(refreshed.socketURL == identity.socketURL)
        #expect(refreshed.idToken == "fresh-token")
        #expect(refreshed.extraHeaders["Authorization"] == "Bearer fresh-token")
        #expect(refreshed.authPayload["idToken"] as? String == "fresh-token")
    }

    @Test
    func replacingIDTokenRejectsEmptyCredential() throws {
        let identity = SocketSessionIdentity(
            uid: "uid-1",
            email: "user@example.com",
            nickname: "",
            avatarPath: nil,
            clientKey: "ios-device",
            socketURL: try #require(URL(string: "https://socket.example.com")),
            idToken: "expired-token"
        )

        #expect(throws: Error.self) {
            _ = try identity.replacingIDToken("   ")
        }
    }
}

struct RealtimeChatIngressOrderingTests {
    @Test func contiguousMessagesReleaseWithoutRecovery() async {
        let loader = RealtimeGapRecoveryLoaderFake(messages: [])
        let actor = makeActor(loader: loader, baselineSeq: 100)

        await actor.start()
        await actor.receive(makeMessage(seq: 101))
        await actor.receive(makeMessage(seq: 102))

        var iterator = actor.messages.makeAsyncIterator()
        let received = [await iterator.next()?.seq, await iterator.next()?.seq]
        let loaderCallCount = await loader.callCount

        #expect(received == [101, 102])
        #expect(loaderCallCount == 0)
        await actor.finish()
    }

    @Test func outOfOrderSocketMessagesReleaseInSequenceAfterRecovery() async {
        let loader = RealtimeGapRecoveryLoaderFake(
            messages: [makeMessage(seq: 101), makeMessage(seq: 102)]
        )
        let actor = makeActor(loader: loader, baselineSeq: 100)

        await actor.start()
        await actor.receive(makeMessage(seq: 102))

        var iterator = actor.messages.makeAsyncIterator()
        let received = [await iterator.next()?.seq, await iterator.next()?.seq]
        let loaderCallCount = await loader.callCount

        #expect(received == [101, 102])
        #expect(loaderCallCount == 1)
        await actor.finish()
    }

    @Test func promotionHighWatermarkStartsRecoveryWithoutNewSocketEvent() async {
        let loader = RealtimeGapRecoveryLoaderFake(
            messages: [101, 102, 103].map { makeMessage(seq: Int64($0)) }
        )
        let actor = makeActor(
            loader: loader,
            baselineSeq: 100,
            promotionHighWatermark: 103
        )

        await actor.start()
        var iterator = actor.messages.makeAsyncIterator()
        let received = [
            await iterator.next()?.seq,
            await iterator.next()?.seq,
            await iterator.next()?.seq
        ]
        let requestedAfterSeqs = await loader.requestedAfterSeqs

        #expect(received == [101, 102, 103])
        #expect(requestedAfterSeqs == [100])
        await actor.finish()
    }

    @Test func recoveryAndRealtimeDuplicateReleaseOnlyOnce() async {
        let loader = RealtimeGapRecoveryLoaderFake(
            messages: [makeMessage(seq: 101), makeMessage(seq: 102)]
        )
        let actor = makeActor(loader: loader, baselineSeq: 100)

        await actor.receive(makeMessage(seq: 102))
        var iterator = actor.messages.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        let snapshot = await actor.snapshot()

        #expect([first?.seq, second?.seq] == [101, 102])
        #expect(snapshot.lastReleasedSeq == 102)
        await actor.finish()
    }

    @Test func recoveryRetriesAtMostThreeTimesAndThenSucceeds() async {
        let loader = RealtimeGapRecoveryLoaderFake(
            messages: [makeMessage(seq: 101)],
            failuresBeforeSuccess: 2
        )
        let actor = makeActor(
            loader: loader,
            baselineSeq: 100,
            promotionHighWatermark: 101
        )

        await actor.start()
        var iterator = actor.messages.makeAsyncIterator()
        let received = await iterator.next()
        let loaderCallCount = await loader.callCount

        #expect(received?.seq == 101)
        #expect(loaderCallCount == 3)
        await actor.finish()
    }

    @Test func exhaustedRecoveryRemainsDegradedWithoutSkippingCheckpoint() async {
        let loader = RealtimeGapRecoveryLoaderFake(
            messages: [],
            failuresBeforeSuccess: 3
        )
        let actor = makeActor(
            loader: loader,
            baselineSeq: 100,
            promotionHighWatermark: 101
        )

        await actor.start()
        await waitUntil { await loader.callCount == 3 }
        await waitUntil { await actor.snapshot().isDegraded }
        let snapshot = await actor.snapshot()
        let loaderCallCount = await loader.callCount

        #expect(snapshot.lastReleasedSeq == 100)
        #expect(snapshot.highestObservedSeq == 101)
        #expect(snapshot.isDegraded)
        #expect(loaderCallCount == 3)
        await actor.finish()
    }

    @Test func pendingPayloadCountStopsAtHardCap() async {
        let loader = SuspendingGapRecoveryLoader()
        let actor = ChatRoomStrictSessionActor(
            roomID: "room",
            baselineSeq: 100,
            promotionHighWatermark: 100,
            recoveryLoader: loader,
            clock: LongRealtimeOrderingClock(),
            pendingRecoveryThreshold: 100,
            pendingHardCap: 300
        )

        for seq in 102...501 {
            await actor.receive(makeMessage(seq: Int64(seq)))
        }
        await waitUntil { await loader.callCount > 0 }
        let snapshot = await actor.snapshot()

        #expect(snapshot.pendingCount == 300)
        #expect(snapshot.requiresAuthoritativeReload)
        #expect(snapshot.highestObservedSeq == 501)
        await actor.finish()
    }

    @Test func suspendKeepsPendingAndRejoinResumesImmediateRecovery() async {
        let loader = RealtimeGapRecoveryLoaderFake(
            messages: [makeMessage(seq: 101), makeMessage(seq: 102)]
        )
        let actor = ChatRoomStrictSessionActor(
            roomID: "room",
            baselineSeq: 100,
            promotionHighWatermark: 100,
            recoveryLoader: loader,
            clock: LongRealtimeOrderingClock()
        )

        await actor.receive(makeMessage(seq: 102))
        await actor.suspend()
        let suspendedSnapshot = await actor.snapshot()
        let callsWhileSuspended = await loader.callCount

        await actor.resumeAfterRejoin()
        var iterator = actor.messages.makeAsyncIterator()
        let received = [await iterator.next()?.seq, await iterator.next()?.seq]
        let resumedSnapshot = await actor.snapshot()

        #expect(suspendedSnapshot.isSuspended)
        #expect(suspendedSnapshot.pendingCount == 1)
        #expect(callsWhileSuspended == 0)
        #expect(received == [101, 102])
        #expect(!resumedSnapshot.isSuspended)
        await actor.finish()
    }

    @Test func suspendedLateIngressDoesNotRestartGapTimer() async {
        let loader = RealtimeGapRecoveryLoaderFake(
            messages: [makeMessage(seq: 101), makeMessage(seq: 102)]
        )
        let clock = CountingRealtimeOrderingClock()
        let actor = ChatRoomStrictSessionActor(
            roomID: "room",
            baselineSeq: 100,
            promotionHighWatermark: 100,
            recoveryLoader: loader,
            clock: clock
        )

        await actor.receive(makeMessage(seq: 102))
        await waitUntil { await clock.sleepCount == 1 }
        await actor.suspend()
        let sleepCountAfterSuspend = await clock.sleepCount

        await actor.receive(makeMessage(seq: 103))
        for _ in 0..<10 { await Task.yield() }
        let finalSleepCount = await clock.sleepCount
        let snapshot = await actor.snapshot()

        #expect(sleepCountAfterSuspend == 1)
        #expect(finalSleepCount == sleepCountAfterSuspend)
        #expect(snapshot.highestObservedSeq == 102)
        #expect(snapshot.pendingCount == 1)
        await actor.finish()
    }

    @Test func rejoinAuditsAfterCheckpointWithoutKnownSocketGap() async {
        let loader = RealtimeGapRecoveryLoaderFake(messages: [makeMessage(seq: 101)])
        let actor = makeActor(loader: loader, baselineSeq: 100)

        await actor.suspend()
        await actor.resumeAfterRejoin()
        var iterator = actor.messages.makeAsyncIterator()
        let received = await iterator.next()
        let requestedAfterSeqs = await loader.requestedAfterSeqs

        #expect(received?.seq == 101)
        #expect(requestedAfterSeqs == [100])
        await actor.finish()
    }

    @Test func terminalRecoveryErrorFinishesStreamWithoutAdvancingCheckpoint() async {
        let actor = makeActor(
            loader: TerminalRealtimeGapRecoveryLoader(),
            baselineSeq: 100,
            promotionHighWatermark: 101
        )

        await actor.start()
        var iterator = actor.messages.makeAsyncIterator()
        let received = await iterator.next()
        let snapshot = await actor.snapshot()

        #expect(received == nil)
        #expect(snapshot.lastReleasedSeq == 100)
        #expect(snapshot.isTerminal)
        #expect(snapshot.isDegraded)
        await actor.finish()
    }

    private func makeActor(
        loader: ChatRealtimeGapRecoveryLoading,
        baselineSeq: Int64,
        promotionHighWatermark: Int64? = nil
    ) -> ChatRoomStrictSessionActor {
        ChatRoomStrictSessionActor(
            roomID: "room",
            baselineSeq: baselineSeq,
            promotionHighWatermark: promotionHighWatermark ?? baselineSeq,
            recoveryLoader: loader,
            clock: ImmediateRealtimeOrderingClock()
        )
    }
}

struct RealtimeRoomJoinStateTests {
    @Test func concurrentJoinRequestsShareOneAttemptUntilAck() {
        var state = RealtimeRoomJoinState()
        let attemptID = UUID()

        let first = state.begin(roomID: "room", attemptID: attemptID)
        let second = state.begin(roomID: "room", attemptID: UUID())

        #expect(first == .started(attemptID))
        #expect(second == .inFlight(attemptID))
        #expect(state.attempts.count == 1)
    }

    @Test func onlyCurrentAttemptCanConfirmMembership() {
        var state = RealtimeRoomJoinState()
        let attemptID = UUID()
        _ = state.begin(roomID: "room", attemptID: attemptID)

        let staleResolved = state.resolve(
            roomID: "room",
            attemptID: UUID(),
            succeeded: true
        )
        let currentResolved = state.resolve(
            roomID: "room",
            attemptID: attemptID,
            succeeded: true
        )

        #expect(staleResolved == false)
        #expect(currentResolved == true)
        #expect(state.begin(roomID: "room") == .alreadyJoined)
    }

    @Test func reconnectInvalidationAllowsOneNewAttempt() {
        var state = RealtimeRoomJoinState()
        let firstAttemptID = UUID()
        let secondAttemptID = UUID()
        _ = state.begin(roomID: "room", attemptID: firstAttemptID)
        _ = state.resolve(roomID: "room", attemptID: firstAttemptID, succeeded: true)

        state.invalidateMembership()
        let result = state.begin(roomID: "room", attemptID: secondAttemptID)

        #expect(result == .started(secondAttemptID))
        #expect(state.isConfirmed("room") == false)
    }
}

struct RealtimeSocketReconnectStateTests {
    @Test func reconnectRequestWhileOfflineSchedulesWhenNetworkReturns() {
        var state = RealtimeSocketReconnectState()
        let attemptID = UUID()

        state.updateNetworkAvailability(false)
        state.requestReconnect()
        let offlineAttempt = state.scheduleIfPossible(
            isAllowed: true,
            maxAttempts: 5,
            attemptID: UUID()
        )

        state.updateNetworkAvailability(true)
        let recoveredAttempt = state.scheduleIfPossible(
            isAllowed: true,
            maxAttempts: 5,
            attemptID: attemptID
        )

        #expect(offlineAttempt == nil)
        #expect(recoveredAttempt == .init(id: attemptID, number: 1))
    }

    @Test func networkRecoveryBeforeDisconnectStillSchedulesReconnect() {
        var state = RealtimeSocketReconnectState()
        let attemptID = UUID()

        state.updateNetworkAvailability(true)
        state.requestReconnect()
        let attempt = state.scheduleIfPossible(
            isAllowed: true,
            maxAttempts: 5,
            attemptID: attemptID
        )

        #expect(attempt == .init(id: attemptID, number: 1))
    }

    @Test func duplicateSignalsKeepOneScheduledAttempt() {
        var state = RealtimeSocketReconnectState()
        let firstID = UUID()

        state.updateNetworkAvailability(true)
        state.requestReconnect()
        let first = state.scheduleIfPossible(
            isAllowed: true,
            maxAttempts: 5,
            attemptID: firstID
        )
        state.requestReconnect()
        let duplicate = state.scheduleIfPossible(
            isAllowed: true,
            maxAttempts: 5,
            attemptID: UUID()
        )

        #expect(first == .init(id: firstID, number: 1))
        #expect(duplicate == nil)
    }

    @Test func offlineTransitionInvalidatesDelayedAttemptWithoutLosingIntent() {
        var state = RealtimeSocketReconnectState()
        let staleID = UUID()
        let nextID = UUID()

        state.updateNetworkAvailability(true)
        state.requestReconnect()
        _ = state.scheduleIfPossible(
            isAllowed: true,
            maxAttempts: 5,
            attemptID: staleID
        )
        state.updateNetworkAvailability(false)

        #expect(state.consumeScheduledAttempt(id: staleID) == false)
        #expect(state.needsReconnect)

        state.updateNetworkAvailability(true)
        let next = state.scheduleIfPossible(
            isAllowed: true,
            maxAttempts: 5,
            attemptID: nextID
        )

        #expect(next == .init(id: nextID, number: 1))
    }

    @Test func offlineWaitUsesOneNetworkProbeAndDoesNotConsumeConnectAttempts() {
        var state = RealtimeSocketReconnectState()
        let firstProbeID = UUID()
        let nextProbeID = UUID()

        state.updateNetworkAvailability(false)
        state.requestReconnect()
        let first = state.scheduleNetworkProbeIfPossible(
            isAllowed: true,
            probeID: firstProbeID
        )
        let duplicate = state.scheduleNetworkProbeIfPossible(
            isAllowed: true,
            probeID: UUID()
        )

        #expect(first == .init(id: firstProbeID, number: 1))
        #expect(duplicate == nil)
        #expect(state.attemptCount == 0)
        let didConsumeFirstProbe = state.consumeScheduledNetworkProbe(id: firstProbeID)
        #expect(didConsumeFirstProbe)

        let next = state.scheduleNetworkProbeIfPossible(
            isAllowed: true,
            probeID: nextProbeID
        )
        #expect(next == .init(id: nextProbeID, number: 2))
        #expect(state.attemptCount == 0)
    }

    @Test func networkRecoveryInvalidatesWaitingProbeAndSchedulesConnect() {
        var state = RealtimeSocketReconnectState()
        let staleProbeID = UUID()
        let attemptID = UUID()

        state.updateNetworkAvailability(false)
        state.requestReconnect()
        _ = state.scheduleNetworkProbeIfPossible(
            isAllowed: true,
            probeID: staleProbeID
        )
        state.updateNetworkAvailability(true)

        let didConsumeStaleProbe = state.consumeScheduledNetworkProbe(id: staleProbeID)
        #expect(didConsumeStaleProbe == false)
        let attempt = state.scheduleIfPossible(
            isAllowed: true,
            maxAttempts: 5,
            attemptID: attemptID
        )
        #expect(attempt == .init(id: attemptID, number: 1))
    }

    @Test func connectWatchdogIsSingleFlightAndConnectedStateInvalidatesIt() {
        var state = RealtimeSocketReconnectState()
        let watchdogID = UUID()

        state.requestReconnect()
        let first = state.scheduleConnectWatchdogIfPossible(watchdogID: watchdogID)
        let duplicate = state.scheduleConnectWatchdogIfPossible(watchdogID: UUID())

        #expect(first == watchdogID)
        #expect(duplicate == nil)

        state.markConnected()
        let didConsumeStaleWatchdog = state.consumeConnectWatchdog(id: watchdogID)
        #expect(didConsumeStaleWatchdog == false)
    }
}

private struct ImmediateRealtimeOrderingClock: RealtimeOrderingClock {
    func sleep(for seconds: TimeInterval) async throws {
        await Task.yield()
    }
}

private struct LongRealtimeOrderingClock: RealtimeOrderingClock {
    func sleep(for seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: 60_000_000_000)
    }
}

private actor CountingRealtimeOrderingClock: RealtimeOrderingClock {
    private(set) var sleepCount = 0

    func sleep(for seconds: TimeInterval) async throws {
        sleepCount += 1
        try await Task.sleep(nanoseconds: 60_000_000_000)
    }
}

private actor RealtimeGapRecoveryLoaderFake: ChatRealtimeGapRecoveryLoading {
    private let messages: [ChatMessage]
    private var failuresRemaining: Int
    private(set) var requestedAfterSeqs: [Int64] = []

    var callCount: Int { requestedAfterSeqs.count }

    init(messages: [ChatMessage], failuresBeforeSuccess: Int = 0) {
        self.messages = messages.sorted { $0.seq < $1.seq }
        self.failuresRemaining = failuresBeforeSuccess
    }

    func fetchMessages(
        roomID: String,
        afterSeq: Int64,
        limit: Int
    ) async throws -> [ChatMessage] {
        requestedAfterSeqs.append(afterSeq)
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw RealtimeOrderingTestError.injected
        }
        return Array(messages.filter { $0.seq > afterSeq }.prefix(limit))
    }
}

private actor SuspendingGapRecoveryLoader: ChatRealtimeGapRecoveryLoading {
    private(set) var callCount = 0

    func fetchMessages(
        roomID: String,
        afterSeq: Int64,
        limit: Int
    ) async throws -> [ChatMessage] {
        callCount += 1
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return []
    }
}

private struct TerminalRealtimeGapRecoveryLoader: ChatRealtimeGapRecoveryLoading {
    func fetchMessages(
        roomID: String,
        afterSeq: Int64,
        limit: Int
    ) async throws -> [ChatMessage] {
        throw ChatRealtimeGapRecoveryError.permissionDenied
    }
}

private enum RealtimeOrderingTestError: Error {
    case injected
}

private func makeMessage(seq: Int64) -> ChatMessage {
    ChatMessage(
        ID: "message-\(seq)",
        seq: seq,
        roomID: "room",
        senderUID: "sender",
        senderEmail: nil,
        senderNickname: "Sender",
        senderAvatarPath: nil,
        messageType: .text,
        msg: "message",
        sentAt: Date(timeIntervalSince1970: TimeInterval(seq)),
        attachments: [],
        replyPreview: nil
    )
}

private func waitUntil(
    attempts: Int = 1_000,
    condition: @escaping () async -> Bool
) async {
    for _ in 0..<attempts {
        if await condition() { return }
        await Task.yield()
    }
}
