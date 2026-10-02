import Foundation
import Testing
@testable import OutPick

@MainActor struct ChatSearchSessionTests {
    typealias F = SearchSessionFixture

    @Test func demandBudgetStopsAtFivePagesAndExplicitContinueKeepsCursor() async throws {
        let f = try F(); let gate = SearchWriteBarrier()
        f.remote.upper = 1_000
        f.visibility.insert("blocked")
        _ = try await GRDBChatDeletionSyncStore(database: f.database).apply([SearchStoreFixture.delta("m-1000", 1)], accountID: "account-1", roomID: "room-1")
        f.remote.pages = (0..<5).map { page in
            .success(F.page((0..<100).map { offset in
                let seq = 1_000 - page * 100 - offset
                return F.message("m-\(seq)", Int64(seq), text: page < 2 ? "ㅋㅋ목표" : "ㅋㅋ다른본문",
                                 author: seq == 1_000 || page >= 2 ? "author" : "blocked")
            }, cursor: "page-\(page)", exhausted: false))
        }
        f.remote.pages.append(.success(F.page([F.message("found", 400, text: "ㅋㅋ목표")])) )
        f.remote.gates[5] = gate
        f.controller.search(roomID: "room-1", keyword: "ㅋㅋ목표")
        try await f.idle(0)
        #expect(f.remote.calls.count == 5 && f.store.commits == 5)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(f.remote.calls.count == 5)
        let id = try #require(f.controller.snapshot?.identity)
        #expect(ChatSearchPresentationState(snapshot: f.controller.snapshot).canContinue)
        f.controller.continueSearch(session: id)
        await gate.waitUntilSuspended()
        for _ in 0..<10 { f.controller.continueSearch(session: id); f.controller.prefetchIfNeeded(session: id) }
        #expect(f.remote.calls.count == 6 && f.remote.calls[5].1 == SearchStoreFixture.cursor("page-4"))
        await gate.release(); try await f.completed(1)
        #expect(f.remote.calls.count == 6 && f.remote.maximumInFlight == 1)
        f.controller.stop()
    }

    @Test func firstDemandAndPrefetchStayIdleWithoutRecursiveSearch() async throws {
        let f = try F()
        f.remote.pages = [.success(F.page((5...17).reversed().map { F.message("m-\($0)", Int64($0)) }, cursor: "first", exhausted: false)),
                          .success(F.page([F.message("collision", 4, text: "ㅋ")], cursor: "second", exhausted: false)),
                          .success(F.page([F.message("last", 3)]))]
        f.controller.search(roomID: "room-1", keyword: "ㅋㅋ")
        try await f.idle(13)
        let id = try #require(f.controller.snapshot?.identity)
        for ordinal in 1...3 {
            let pending = try #require(try await f.controller.prepareNavigation(session: id, direction: .older))
            try await f.controller.commitNavigation(pending)
            f.controller.prefetchIfNeeded(session: id)
            if ordinal < 3 {
                await f.controller.active?.task?.value
                #expect(f.remote.calls.count == 1)
            }
        }
        try await F.until { f.remote.calls.count == 2 && f.controller.active?.task == nil }
        try await f.idle(13)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(f.remote.calls.count == 2)
        f.controller.setForeground(false); f.controller.setForeground(true)
        try await f.idle(13)
        #expect(f.remote.calls.count == 2)
        let next = try #require(try await f.controller.prepareNavigation(session: id, direction: .older))
        try await f.controller.commitNavigation(next)
        f.controller.prefetchIfNeeded(session: id)
        try await f.completed(14)
        #expect(f.remote.calls.count == 3 && f.remote.calls[2].1 == SearchStoreFixture.cursor("second"))
        f.controller.stop()
    }

    @Test func navigationAndExactCountShareOneScanAndCommitEachPageOnce() async throws {
        let f = try F()
        let gate = SearchWriteBarrier()
        f.remote.pages = [.success(F.page([F.message("false-positive", 9, text: "ㅋ")], cursor: "first", exhausted: false)),
                          .success(F.page([F.message("latest", 8), F.message("older", 7)]))]
        f.remote.gates[1] = gate
        f.controller.search(roomID: "room-1", keyword: "ㅋㅋ")
        await gate.waitUntilSuspended()
        let id = try #require(f.controller.snapshot?.identity)
        let waiting = Task { try await f.controller.prepareNavigation(session: id, direction: .older) }
        await Task.yield()
        await gate.release()
        let first = try #require(try await waiting.value)
        #expect(first.target.messageID == "latest")
        #expect(f.controller.snapshot?.committedOrdinal == nil)
        try await f.controller.commitNavigation(first)
        let second = try #require(try await f.controller.prepareNavigation(session: id, direction: .older))
        try await f.controller.commitNavigation(second)
        try await f.completed(2)
        #expect(f.controller.snapshot?.committedOrdinal == 2)
        #expect(f.remote.calls.count == 2 && f.remote.maximumInFlight == 1 && f.store.commits == 2)
        #expect(f.remote.calls[0].1 == nil)
        #expect(f.remote.calls[1].1 == SearchStoreFixture.cursor("first"))
        f.controller.stop()
    }

    @Test func firstHitPublishesBeforeExhaustionWithoutPrematureZeroCount() async throws {
        let f = try F(); let gate = SearchWriteBarrier()
        f.remote.pages = [.success(F.page([F.message("first", 9)], exhausted: false)), .success(F.page([F.message("last", 8)]))]
        f.remote.gates[1] = gate
        f.controller.search(roomID: "room-1", keyword: "ㅋㅋ")
        try await f.continueAfterIdle(1)
        await gate.waitUntilSuspended()
        #expect(f.controller.snapshot?.count == .scanning(knownCount: 1))
        #expect(!f.emissions.contains { $0?.count == .completed(totalCount: 0) })
        let id = try #require(f.controller.snapshot?.identity)
        let pending = try #require(try await f.controller.prepareNavigation(session: id, direction: .older))
        try await f.controller.commitNavigation(pending)
        #expect(f.controller.snapshot?.committedOrdinal == 1)
        await gate.release(); try await f.completed(2)
        #expect(f.controller.snapshot?.selectedMessageID == "first")
        f.controller.stop()
    }

    @Test func replacementAndCancellationDiscardStaleResponsesAndNextRequests() async throws {
        let f = try F(); let gate = SearchWriteBarrier()
        f.remote.pages = [.success(F.page([F.message("old", 9)], exhausted: false)), .success(F.page([F.message("new", 8, text: "새 검색")]))]
        f.remote.gates[0] = gate
        f.controller.search(roomID: "room-1", keyword: "ㅋㅋ")
        await gate.waitUntilSuspended()
        let oldRun = try #require(f.controller.active)
        f.controller.search(roomID: "room-1", keyword: "새")
        try await f.completed(1)
        let id = try #require(f.controller.snapshot?.identity)
        #expect(id != oldRun.identity)
        await gate.release()
        try await F.until { oldRun.task == nil }
        #expect(f.remote.calls.count == 2 && f.controller.snapshot?.identity == id)
        let pending = try #require(try await f.controller.prepareNavigation(session: id, direction: .older))
        #expect(pending.target.messageID == "new")
        await f.controller.cancel(session: id)
        #expect(f.controller.snapshot == nil)

        let g = try F(); let cancelGate = SearchWriteBarrier()
        g.remote.pages = [.success(F.page([F.message("cancelled", 9)], exhausted: false))]
        g.remote.gates[0] = cancelGate
        g.controller.search(roomID: "room-1", keyword: "ㅋㅋ")
        await cancelGate.waitUntilSuspended()
        let run = try #require(g.controller.active)
        await g.controller.cancel(session: run.identity); await cancelGate.release()
        try await F.until { run.task == nil }
        #expect(g.controller.snapshot == nil && g.remote.calls.count == 1 && g.store.commits == 0)
    }

    @Test func backgroundPausesNewWorkAndForegroundRevalidatesBeforeResume() async throws {
        let f = try F(); let pageGate = SearchWriteBarrier(); let accessGate = SearchWriteBarrier()
        f.remote.pages = [.success(F.page([F.message("first", 9)], cursor: "resume", exhausted: false)), .success(F.page([F.message("last", 8)]))]
        f.remote.gates[0] = pageGate
        f.controller.search(roomID: "room-1", keyword: "ㅋㅋ")
        await pageGate.waitUntilSuspended()
        f.controller.setForeground(false); await pageGate.release()
        try await F.until { f.controller.active?.task == nil }
        #expect(f.store.commits == 1 && f.remote.calls.count == 1)
        let id = try #require(f.controller.snapshot?.identity)
        let paused = try await f.controller.prepareNavigation(session: id, direction: .older)
        #expect(paused == nil)
        f.validation.accessGate = accessGate
        f.controller.setForeground(true)
        await accessGate.waitUntilSuspended()
        #expect(f.controller.snapshot?.isRefreshing == true && f.remote.calls.count == 1)
        await accessGate.release(); try await f.idle(1)
        #expect(f.remote.calls.count == 1)
        try await f.continueAfterIdle(1); try await f.completed(2)
        #expect(f.remote.calls[1].1 == SearchStoreFixture.cursor("resume"))
        f.controller.stop()
    }

    @Test func errorsResumeOnlyAllowedCursorWithoutAutomaticRetryLoop() async throws {
        let f = try F()
        f.remote.pages = [.success(F.page([F.message("one", 9)]))]
        f.store.failCommit = true
        f.controller.search(roomID: "room-1", keyword: "ㅋㅋ")
        try await F.until { f.controller.snapshot?.count == .failed(.localStorage) && f.controller.active?.task == nil }
        let id = try #require(f.controller.snapshot?.identity)
        #expect(f.remote.calls.count == 1 && f.store.commits == 0 && f.local.opens == 0)
        f.controller.retry(); try await f.completed(1)
        #expect(f.controller.snapshot?.identity == id && f.remote.calls.count == 1 && f.store.commits == 1)
        f.controller.stop()

        // 페이지는 저장됐지만 count 읽기가 실패해도 cursor를 되감지 않고 유효한 기존 선택을 보존한다.
        let retained = try F(); let nextPage = SearchWriteBarrier()
        retained.remote.pages = [.success(F.page([F.message("selected", 9)], cursor: "saved", exhausted: false)),
                                 .success(F.page([F.message("second", 8)]))]
        retained.remote.gates[1] = nextPage
        retained.controller.search(roomID: "room-1", keyword: "ㅋㅋ")
        try await retained.continueAfterIdle(1)
        await nextPage.waitUntilSuspended()
        let retainedID = try #require(retained.controller.snapshot?.identity)
        let selected = try #require(try await retained.controller.prepareNavigation(session: retainedID, direction: .older))
        try await retained.controller.commitNavigation(selected)
        retained.store.failState = true; await nextPage.release()
        try await F.until { retained.controller.snapshot?.count == .failed(.localStorage) && retained.controller.active?.task == nil }
        #expect(retained.controller.snapshot?.selectedMessageID == "selected" && retained.controller.snapshot?.committedOrdinal == 1)
        retained.controller.retry(); try await retained.completed(2)
        #expect(retained.remote.calls.count == 2 && retained.store.commits == 2)
        retained.controller.stop()

        for failure in [ChatSearchFailure.indexConfiguration, .malformedData, .incompatibleIndexVersion] {
            let g = try F()
            g.remote.pages = [.failure(failure), .success(F.page([F.message("retry", 8)]))]
            g.controller.search(roomID: "room-1", keyword: "ㅋㅋ")
            try await F.until { g.controller.snapshot?.count == .failed(failure) && g.controller.active?.task == nil }
            let oldID = g.controller.snapshot?.identity
            #expect(g.remote.calls.count == 1 && g.local.opens == 0)
            g.controller.retry(); try await g.completed(1)
            #expect(g.controller.snapshot?.identity != oldID && g.remote.upperCalls == 2 && g.remote.calls[1].1 == nil)
            g.controller.stop()
        }
    }
}
