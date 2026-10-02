import Foundation
import Testing
@testable import OutPick

@MainActor struct ChatSearchVisibilityTests {
    typealias F = SearchSessionFixture
    @Test func blockPublicationFenceRejectsStaleResultsAndJumpCompletions() async throws {
        let f = try F(); let gate = SearchWriteBarrier()
        f.remote.pages = [.success(F.page([F.message("blocked", 9, author: "blocked"), F.message("visible", 8)]))]
        f.store.afterCommit = gate
        f.controller.search(roomID: "room-1", keyword: "ㅋㅋ")
        await gate.waitUntilSuspended()
        f.visibility.insert("blocked")
        #expect(f.controller.snapshot?.isRefreshing == true && f.controller.snapshot?.selectedMessageID == nil)
        let revision = f.visibility.snapshot().revision
        await gate.release(); try await f.completed(1)
        #expect(f.controller.snapshot?.visibilityRevision == revision && f.remote.calls.count == 1)
        let id = try #require(f.controller.snapshot?.identity)
        let pending = try #require(try await f.controller.prepareNavigation(session: id, direction: .older))
        #expect(pending.target.messageID == "visible")
        f.visibility.insert("author")
        do { try await f.controller.commitNavigation(pending); Issue.record("차단 전 이동 토큰이 승인됨") }
        catch is CancellationError {} catch { throw error }
        try await f.completed(0)
        #expect(f.controller.snapshot?.committedOrdinal == nil)
        f.controller.stop()

        let g = try F(); let stateGate = SearchWriteBarrier()
        g.remote.pages = [.success(F.page([F.message("stale", 9, author: "blocked")]))]
        g.store.afterState = stateGate
        g.controller.search(roomID: "room-1", keyword: "ㅋㅋ")
        await stateGate.waitUntilSuspended()
        g.visibility.insert("blocked")
        let boundary = g.emissions.count
        await stateGate.release(); try await g.completed(0)
        #expect(!g.emissions.dropFirst(boundary).contains { $0?.count == .completed(totalCount: 1) })
        g.controller.stop()

        // 차단 DB write가 먼저 끝난 뒤 구 revision page를 재처리하되 서버를 다시 조회하지 않는다.
        let h = try F(); let commitGate = SearchWriteBarrier()
        h.remote.pages = [.success(F.page([F.message("late", 9, author: "blocked")]))]
        h.store.beforeCommit = commitGate
        h.controller.search(roomID: "room-1", keyword: "ㅋㅋ")
        await commitGate.waitUntilSuspended()
        h.visibility.insert("blocked")
        let current = h.visibility.snapshot()
        let identity = try #require(h.controller.snapshot?.identity)
        _ = try await h.store.base.applyVisibility(identity: identity, revision: current.revision, blockedAuthorIDs: current.blockedIDs)
        await commitGate.release(); try await h.completed(0)
        #expect(h.remote.calls.count == 1 && h.store.commits == 1)
        h.controller.stop()

        // 삭제 시작부터 실제 marker transaction 종료까지 이전 집계와 이동을 공개하지 않는다.
        let d = try F()
        d.remote.pages = [.success(F.page([F.message("deleted", 9)]))]
        d.controller.search(roomID: "room-1", keyword: "ㅋㅋ"); try await d.completed(1)
        let deletion = d.fence.begin(roomID: "room-1")
        await Task.yield()
        #expect(d.controller.snapshot?.isRefreshing == true)
        _ = try await GRDBChatDeletionSyncStore(database: d.database).apply([SearchStoreFixture.delta("deleted", 1)], accountID: "account-1", roomID: "room-1")
        d.fence.finish(deletion, succeeded: true)
        try await d.completed(0)
        #expect(d.remote.calls.count == 1)
        d.controller.stop()

        let wired = try F()
        wired.remote.pages = [.success(F.page([F.message("socket-deleted", 9)]))]
        wired.controller.search(roomID: "room-1", keyword: "ㅋㅋ"); try await wired.completed(1)
        let deletionUseCase = ChatDeletionSyncUseCase(repository: SearchRecoveryRepository(head: 0, rows: []),
            persistence: GRDBChatDeletionSyncStore(database: wired.database), mediaCleaner: SearchNoopCleaner(), searchFence: wired.fence)
        let boundaryCount = wired.emissions.count
        _ = try await deletionUseCase.handleSocketEvent(ChatDeletionSocketEvent(roomID: "room-1",
            kind: .message(SearchStoreFixture.delta("socket-deleted", 1))), accountID: "account-1")
        try await wired.completed(0)
        // actor 요청 시작과 실제 삭제 write 무효화 사이의 정상 발행은 허용한다.
        let fenced = try #require(wired.emissions.indices.dropFirst(boundaryCount).first { wired.emissions[$0]?.isRefreshing == true })
        #expect(!wired.emissions.dropFirst(fenced).contains { $0?.count == .completed(totalCount: 1) })
        wired.controller.stop()
    }

    @Test func reversedSnapshotsUnblockAndAccountEpochNeverRestoreInvalidHits() async throws {
        let f = try F()
        f.remote.pages = [.success(F.page([F.message("blocked", 9, author: "blocked"), F.message("visible", 8)])),
                          .success(F.page([F.message("blocked", 9, author: "blocked"), F.message("visible", 8)]))]
        f.controller.search(roomID: "room-1", keyword: "ㅋㅋ"); try await f.completed(2)
        let old = f.visibility.snapshot()
        f.visibility.insert("blocked")
        f.visibility.remove("blocked")
        f.visibility.insert("blocked")
        try await f.completed(1)
        f.controller.receiveVisibility(old)
        #expect(f.controller.snapshot?.visibilityRevision != old.revision)
        f.visibility.remove("blocked"); try await f.completed(1)
        f.controller.search(roomID: "room-1", keyword: "ㅋㅋ"); try await f.completed(2)
        let epoch = f.controller.snapshot?.identity.accountEpoch
        f.visibility.beginSession(accountID: "account-1", cachedIDs: [])
        #expect(f.visibility.snapshot().accountEpoch != epoch)
        #expect(f.controller.active == nil && f.controller.snapshot?.count == .failed(.accessLost))

        let g = try F(); let pageGate = SearchWriteBarrier()
        g.remote.pages = [.success(F.page([F.message("old-epoch", 9)], exhausted: false))]
        g.remote.gates[0] = pageGate
        g.controller.search(roomID: "room-1", keyword: "ㅋㅋ")
        await pageGate.waitUntilSuspended()
        let oldRun = try #require(g.controller.active)
        let oldSnapshot = g.visibility.snapshot()
        g.visibility.beginSession(accountID: "account-2", cachedIDs: [])
        g.visibility.beginSession(accountID: "account-1", cachedIDs: [])
        g.controller.receiveVisibility(oldSnapshot)
        await pageGate.release(); try await F.until { oldRun.task == nil }
        #expect(g.controller.active == nil && g.store.commits == 0 && g.remote.calls.count == 1)
    }

    @Test func visibilityWriteFailureHidesResultsUntilLatestSnapshotCommits() async throws {
        let f = try F()
        f.remote.pages = [.success(F.page([F.message("blocked", 9, author: "blocked"), F.message("other", 8, author: "other")]))]
        f.controller.search(roomID: "room-1", keyword: "ㅋㅋ"); try await f.completed(2)
        let id = try #require(f.controller.snapshot?.identity)
        let pending = try #require(try await f.controller.prepareNavigation(session: id, direction: .older))
        try await f.controller.commitNavigation(pending)
        f.store.failVisibility = true
        f.visibility.insert("blocked")
        try await F.until { f.controller.snapshot?.count == .failed(.localStorage) && f.controller.active?.task == nil }
        f.visibility.insert("other")
        #expect(f.controller.snapshot?.isRefreshing == true && f.controller.snapshot?.selectedMessageID == nil)
        #expect(f.remote.calls.count == 1)
        f.store.failVisibility = false; f.controller.retry(); try await f.completed(0)
        #expect(f.controller.snapshot?.identity == id && f.controller.snapshot?.visibilityRevision == f.visibility.snapshot().revision)
        #expect(f.remote.calls.count == 1)
        f.controller.stop()
    }
}
