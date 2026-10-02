import Foundation
import Testing
@testable import OutPick

@MainActor struct ChatSearchNavigationTests {
    @Test func repeatedContextTombstoneDoesNotRestartAutomaticSelection() async throws {
        let f = try SearchNavigationFixture()
        let deletion = ChatDeletionSyncUseCase(repository: SearchRecoveryRepository(head: 0, rows: []),
            persistence: GRDBChatDeletionSyncStore(database: f.source.database),
            mediaCleaner: SearchNoopCleaner(), searchFence: f.source.fence)
        var tombstone = SearchSessionFixture.message("nearby-deleted", 10)
        tombstone.isDeleted = true; tombstone.deletionRevision = 1
        tombstone.deletedAt = Date(timeIntervalSince1970: 50.123456)
        f.sanitizeContext = { messages in
            try await deletion.sanitize(messages + [tombstone], accountID: "account-1", roomID: "room-1")
        }
        defer { f.presentation.stop() }
        f.presentation.start("ㅋㅋ")
        try await f.selected("latest")
        try await SearchSessionFixture.until { !f.presentation.state.isLoading }
        #expect(f.loads.count <= 2 && f.successfulDisplays == ["latest"])
        let stableLoads = f.loads.count
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(f.loads.count == stableLoads && f.source.remote.calls.count == 1)
        f.presentation.move(.older)
        try await f.selected("middle")
        #expect(f.loads.count == stableLoads + 1)
        #expect(f.presentation.snapshot?.committedOrdinal == 2)
    }

    @Test func onlyUserOlderMovementPrefetchesAndContinueAdvancesFromBoundary() async throws {
        let f = try SearchNavigationFixture()
        f.source.remote.pages = [.success(SearchSessionFixture.page((4...16).reversed().map {
            SearchSessionFixture.message("m-\($0)", Int64($0))
        }, cursor: "first", exhausted: false)),
        .success(SearchSessionFixture.page([SearchSessionFixture.message("collision", 3, text: "ㅋ")], cursor: "second", exhausted: false))]
        f.presentation.start("ㅋㅋ"); try await f.selected("m-16"); try await f.source.idle(13)
        #expect(f.source.remote.calls.count == 1 && f.presentation.state.title == "1/13")
        f.presentation.move(.older); try await f.selected("m-15")
        try await SearchSessionFixture.until { !f.presentation.state.isLoading }
        #expect(f.source.remote.calls.count == 1)
        f.presentation.move(.older); try await f.selected("m-14")
        try await SearchSessionFixture.until { f.source.remote.calls.count == 2 && f.source.controller.active?.task == nil }
        f.presentation.move(.newer); try await f.selected("m-15")
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(f.source.remote.calls.count == 2)
        f.presentation.stop()

        let g = try SearchNavigationFixture()
        g.source.remote.pages = [.success(SearchSessionFixture.page([SearchSessionFixture.message("first", 9)], cursor: "first", exhausted: false)),
                                .success(SearchSessionFixture.page([SearchSessionFixture.message("second", 8)], cursor: "second", exhausted: false))]
        g.presentation.start("ㅋㅋ"); try await g.selected("first"); try await g.source.idle(1)
        #expect(g.presentation.state.canContinue && g.source.remote.calls.count == 1)
        g.presentation.retry(); try await g.selected("second"); try await g.source.idle(2)
        #expect(g.presentation.state.title == "2/2" && g.presentation.state.canContinue && g.source.remote.calls.count == 2)
        g.source.visibility.insert("author")
        try await g.source.idle(0)
        #expect(g.presentation.highlightedID == nil && g.presentation.state.canContinue && g.source.remote.calls.count == 2)
        g.presentation.stop()
    }

    @Test func removalUsesAcquiredNewerNeighborWithoutScanningOlderHistory() async throws {
        let f = try SearchNavigationFixture()
        f.source.remote.pages = [.success(SearchSessionFixture.page([
            SearchSessionFixture.message("latest", 9), SearchSessionFixture.message("removed", 8, author: "blocked")
        ], exhausted: false))]
        f.presentation.start("ㅋㅋ"); try await f.selected("latest")
        f.presentation.move(.older, prefetch: false); try await f.selected("removed")
        f.source.visibility.insert("blocked")
        try await f.selected("latest"); try await f.source.idle(1)
        #expect(f.source.remote.calls.count == 1 && f.presentation.state.title == "1/1")
        f.presentation.stop()
    }
    @Test func rapidArrowsCoalesceAndOnlyLatestSuccessfulJumpCommitsOrdinal() async throws {
        let f = try SearchNavigationFixture(); let display = SearchWriteBarrier()
        f.displayGate = display
        f.presentation.start("ㅋㅋ")
        await display.waitUntilSuspended()
        #expect(f.presentation.snapshot?.committedOrdinal == nil)
        #expect(f.presentation.state.title == "3")
        f.presentation.move(.older); f.presentation.move(.newer); f.presentation.move(.older)
        await display.release()
        try await f.selected("latest")
        #expect(f.successfulDisplays == ["latest"] && f.loads.count == 2)
        #expect(f.presentation.state.title == "1/3")
        f.presentation.move(.older); try await f.selected("middle")
        #expect(f.presentation.snapshot?.committedOrdinal == 2)
        #expect(f.presentation.state.title == "2/3")
        f.presentation.move(.newer); try await f.selected("latest")
        #expect(f.source.remote.calls.count == 1 && f.maximumLoads == 1)
        f.presentation.suspend(); f.presentation.resume(); f.presentation.resume()
        try await SearchSessionFixture.until { f.presentation.snapshot?.isRefreshing == false }
        #expect(f.source.remote.calls.count == 1)
        f.presentation.stop()
    }

    @Test func loadOrSnapshotFailureKeepsValidSelectionAndRejectsStaleCompletion() async throws {
        let f = try SearchNavigationFixture()
        f.presentation.start("ㅋㅋ"); try await f.selected("latest")
        f.failLoad = true; f.presentation.move(.older)
        try await f.failedMovement()
        #expect(f.presentation.snapshot?.selectedMessageID == "latest" && f.presentation.snapshot?.committedOrdinal == 1)
        #expect(f.presentation.state.title == "1/3")
        f.failLoad = false; f.failDisplay = true; f.presentation.retry()
        try await f.failedMovement()
        #expect(f.presentation.highlightedID == "latest")
        f.failDisplay = false; f.presentation.retry(); try await f.selected("middle")

        let oldLoad = SearchWriteBarrier(); f.loadGate = oldLoad
        f.presentation.move(.older); await oldLoad.waitUntilSuspended()
        f.source.remote.pages.append(.success(SearchSessionFixture.page([SearchSessionFixture.message("new", 10, text: "새 검색")])) )
        f.presentation.start("새")
        await oldLoad.release(); try await f.selected("new")
        #expect(!f.successfulDisplays.contains("oldest"))
        #expect(f.presentation.snapshot?.committedOrdinal == 1)
        f.presentation.stop()

        let lost = try SearchNavigationFixture()
        lost.presentation.start("ㅋㅋ"); try await lost.selected("latest")
        lost.loadFailure = .accessLost; lost.presentation.move(.older)
        try await SearchSessionFixture.until { lost.presentation.snapshot?.count == .failed(.accessLost) }
        #expect(lost.source.controller.active == nil && lost.presentation.highlightedID == nil)
        #expect(lost.presentation.state.actionTitle == nil && lost.source.local.opens == 0)
        lost.presentation.stop()
    }

    @Test func stateRenderingSeparatesScanningEmptyLocalErrorAndUnselected() throws {
        let identity = try SearchStoreFixture.scope().identity
        func snapshot(_ count: ChatSearchCountState, ordinal: Int? = nil, source: ChatMessageSearchSource = .serverIndex) -> ChatSearchSessionSnapshot {
            ChatSearchSessionSnapshot(identity: identity, source: source, visibilityRevision: 1, count: count,
                selectedMessageID: ordinal == nil ? nil : "one", committedOrdinal: ordinal)
        }
        #expect(ChatSearchPresentationState(snapshot: snapshot(.unknown)).title == "검색 중…")
        #expect(ChatSearchPresentationState(snapshot: snapshot(.scanning(knownCount: 0))).title != "검색 결과 없음")
        #expect(ChatSearchPresentationState(snapshot: snapshot(.scanning(knownCount: 5), ordinal: 1)).title == "1/5")
        #expect(ChatSearchPresentationState(snapshot: snapshot(.completed(totalCount: 5))).title == "5")
        #expect(ChatSearchPresentationState(snapshot: snapshot(.completed(totalCount: 5), ordinal: 2)).title == "2/5")
        let waiting = ChatSearchPresentationState(snapshot: snapshot(.scanning(knownCount: 0)))
        #expect(waiting.title == "0" && waiting.canContinue && !waiting.isLoading)
        let boundary = ChatSearchPresentationState(snapshot: snapshot(.scanning(knownCount: 5), ordinal: 5))
        #expect(boundary.canContinue && !boundary.canMoveOlder && boundary.canMoveNewer)
        let local = ChatSearchPresentationState(snapshot: snapshot(.completed(totalCount: 0), source: .localOffline))
        #expect(local.title == "검색 결과 없음" && local.notice == "검색 결과 수가 제한될 수 있습니다." && local.actionTitle == "다시 검색")
        let error = ChatSearchPresentationState(snapshot: snapshot(.failed(.indexConfiguration)))
        #expect(error.actionTitle == "다시 시도" && !error.canMoveOlder && !error.canMoveNewer)
        let lost = ChatSearchPresentationState(snapshot: snapshot(.failed(.accessLost)))
        #expect(lost.actionTitle == nil)
    }

    @Test func knownCountUpdatesWithoutLoadingIndicatorDuringMovementAndPrefetch() throws {
        let identity = try SearchStoreFixture.scope().identity
        func makeSnapshot(_ count: ChatSearchCountState, ordinal: Int? = nil, fetching: Bool = false) -> ChatSearchSessionSnapshot {
            ChatSearchSessionSnapshot(identity: identity, source: .serverIndex,
                visibilityRevision: 1, count: count, selectedMessageID: ordinal == nil ? nil : "one",
                committedOrdinal: ordinal, isFetching: fetching)
        }
        var snapshot = makeSnapshot(.unknown)
        #expect(ChatSearchPresentationState(snapshot: snapshot).showsLoadingIndicator)
        snapshot = makeSnapshot(.scanning(knownCount: 13), ordinal: 3, fetching: true)
        let fetching = ChatSearchPresentationState(snapshot: snapshot, moving: true)
        #expect(fetching.title == "3/13" && fetching.isLoading && !fetching.showsLoadingIndicator)
        snapshot = makeSnapshot(.scanning(knownCount: 14), ordinal: 3)
        let updated = ChatSearchPresentationState(snapshot: snapshot)
        #expect(updated.title == "3/14" && !updated.showsLoadingIndicator)
        #expect(updated.canMoveOlder && updated.canMoveNewer)
        snapshot = makeSnapshot(.completed(totalCount: 14), ordinal: 3)
        #expect(ChatSearchPresentationState(snapshot: snapshot).actionTitle == nil)
        snapshot = makeSnapshot(.scanning(knownCount: 14), ordinal: 14)
        #expect(ChatSearchPresentationState(snapshot: snapshot).actionTitle == "계속 찾기")
        let failedMove = ChatSearchPresentationState(snapshot: snapshot, movementFailed: true)
        #expect(failedMove.actionTitle == "다시 시도" && failedMove.notice != nil)
    }

    @Test func searchWindowNeverAdvancesReadFrontier() throws {
        let f = try SearchNavigationFixture()
        let viewModel = ChatRoomViewModelMessageActionTests.makeSearchTestViewModel(search: f.presentation)
        let message = SearchSessionFixture.message("target", 100)
        viewModel.applyInitialMessageSyncState(ChatInitialSessionState(window: ChatInitialWindow(messages: [message],
            readBoundarySeq: 10, latestSeq: 100, hasMoreOlder: true, hasMoreNewer: false)))
        f.presentation.start("ㅋㅋ")
        viewModel.applyVisibleWindowAfterSearchJump([message])
        #expect(viewModel.recordVisibleMessage(highestVisibleSeq: 100, contiguousLoadedThroughSeq: 100) == nil)
        viewModel.consumeHiddenLiveMessage(SearchSessionFixture.message("hidden", 11))
        #expect(viewModel.readFrontierSeq == 10 && viewModel.finalLastReadSeqForSessionEnd() == 10)
        f.presentation.stop()
        #expect(viewModel.recordVisibleMessage(highestVisibleSeq: 11, contiguousLoadedThroughSeq: 11) == 11)
    }

    @Test func fallbackDeletionAndBlockChooseDeterministicValidNeighbor() async throws {
        let f = try SearchNavigationFixture()
        f.presentation.start("ㅋㅋ"); try await f.selected("latest")
        f.presentation.move(.older); try await f.selected("middle")
        let deletion = f.source.fence.begin(roomID: "room-1")
        #expect(f.presentation.highlightedID == nil)
        _ = try await GRDBChatDeletionSyncStore(database: f.source.database).apply([SearchStoreFixture.delta("middle", 1)], accountID: "account-1", roomID: "room-1")
        f.source.fence.finish(deletion, succeeded: true)
        try await f.selected("oldest")
        #expect(f.presentation.snapshot?.committedOrdinal == 2)
        f.failDisplay = true
        f.source.visibility.insert("oldest-author")
        try await f.failedMovement()
        #expect(f.presentation.highlightedID == nil && f.presentation.snapshot?.committedOrdinal == nil)
        f.failDisplay = false; f.presentation.retry(); try await f.selected("latest")
        #expect(f.presentation.snapshot?.committedOrdinal == 1)
        f.presentation.stop()

        let g = try SearchNavigationFixture(); let networkFailure = SearchWriteBarrier()
        g.source.remote.pages = [.success(SearchSessionFixture.page([SearchSessionFixture.message("latest", 9)], exhausted: false)), .failure(.transientNetwork)]
        g.source.remote.gates[1] = networkFailure
        try await g.source.seed([SearchSessionFixture.message("local", 8)])
        g.presentation.start("ㅋㅋ"); try await g.selected("latest")
        g.presentation.retry()
        await networkFailure.waitUntilSuspended()
        g.failDisplay = true; await networkFailure.release(); try await g.failedMovement()
        #expect(g.presentation.snapshot?.isLimited == true && g.presentation.snapshot?.committedOrdinal == nil)
        #expect(g.presentation.highlightedID == nil)
        g.failDisplay = false; g.presentation.retry(); try await g.selected("local")
        #expect(g.presentation.snapshot?.committedOrdinal == 1 && g.source.remote.calls.count == 2)
        g.presentation.stop()
    }
}

@MainActor private final class SearchNavigationFixture {
    let source: SearchSessionFixture
    var presentation: ChatSearchPresentationController!
    var loads: [String] = []
    var successfulDisplays: [String] = []
    var loadGate: SearchWriteBarrier?
    var displayGate: SearchWriteBarrier?
    var failLoad = false
    var loadFailure: ChatSearchFailure?
    var failDisplay = false
    var sanitizeContext: (([ChatMessage]) async throws -> [ChatMessage])?
    var activeLoads = 0
    var maximumLoads = 0
    init() throws {
        source = try SearchSessionFixture()
        source.remote.pages = [.success(SearchSessionFixture.page([
            SearchSessionFixture.message("latest", 9), SearchSessionFixture.message("middle", 8),
            SearchSessionFixture.message("oldest", 7, author: "oldest-author")]))]
        presentation = ChatSearchPresentationController(roomID: "room-1", session: ChatRoomSearchSessionUseCase(manager: source.controller)) { [weak self] target, _ in
            guard let self else { throw CancellationError() }
            loads.append(target.messageID); activeLoads += 1; maximumLoads = max(maximumLoads, activeLoads)
            defer { activeLoads -= 1 }
            if let gate = loadGate { loadGate = nil; await gate.suspend() }
            if failLoad { throw ChatSearchFailure.transientNetwork }
            if let loadFailure { throw loadFailure }
            let messages = [SearchSessionFixture.message(target.messageID, target.seq)]
            if let sanitizeContext { return try await sanitizeContext(messages) }
            return messages
        }
        presentation.display = { [weak self] _, target, valid in
            guard let self else { return false }
            if let gate = displayGate { displayGate = nil; await gate.suspend() }
            guard valid(), !failDisplay else { return false }
            successfulDisplays.append(target)
            return true
        }
    }
    func selected(_ id: String) async throws { try await SearchSessionFixture.until { self.presentation.snapshot?.selectedMessageID == id } }
    func failedMovement() async throws { try await SearchSessionFixture.until { self.presentation.state.notice?.contains("이동하지 못했습니다") == true } }
}
