import Foundation
import Testing
@testable import OutPick

@MainActor struct ChatSearchFallbackTests {
    typealias F = SearchSessionFixture
    @Test func offlineAndMidScanFallbackUseOneLocalGenerationAndLiteralScope() async throws {
        let f = try F(); f.network.online = false
        try await f.seed([F.message("literal", 4, text: "50%_ ㅋㅋㅋㅋ"), F.message("wildcard", 3, text: "500 ㅋㅋ"), F.message("pending", 0, text: "50%_")])
        f.controller.search(roomID: "room-1", keyword: "%_")
        try await f.completed(1)
        #expect(f.controller.snapshot?.source == .localOffline && f.controller.snapshot?.isLimited == true)
        #expect(f.remote.calls.isEmpty && f.local.opens == 1)
        f.controller.stop()

        // 후보 본문은 같은 읽기 snapshot에서 순회하므로 일반 캐시 prune의 영향을 받지 않는다.
        let snapshot = try await f.local.openSearchSnapshot(roomID: "room-1")
        let upper = try await snapshot.upperSequence()
        try await f.seed((10...3310).map { F.message("new-\($0)", Int64($0), text: "unrelated") })
        let pinned = try await snapshot.page(upperSeq: upper, after: nil, limit: 100)
        #expect(Set(pinned.candidates.map(\.ID)) == ["literal", "wildcard"])
        let pruned = try await GRDBChatMessageStore(database: f.database).fetchMessage(id: "literal", inRoom: "room-1")
        #expect(pruned == nil)

        let g = try F(); let gate = SearchWriteBarrier()
        try await g.seed([F.message("selected", 9), F.message("local", 8), F.message("too-new", 101)])
        g.remote.pages = [.success(F.page([F.message("selected", 9)], exhausted: false)), .failure(.transientNetwork)]
        g.remote.gates[1] = gate
        g.controller.search(roomID: "room-1", keyword: "ㅋㅋ")
        try await g.continueAfterIdle(1)
        await gate.waitUntilSuspended()
        let oldID = try #require(g.controller.snapshot?.identity)
        let first = try #require(try await g.controller.prepareNavigation(session: oldID, direction: .older))
        try await g.controller.commitNavigation(first)
        await gate.release(); try await g.completed(2)
        let newID = try #require(g.controller.snapshot?.identity)
        #expect(newID != oldID && g.controller.snapshot?.source == .localFallbackAfterServerFailure)
        #expect(g.controller.active?.scope?.upperSeq == 100 && g.local.opens == 1 && g.remote.calls.count == 2)
        let preserved = try #require(try await g.controller.prepareNavigation(session: newID, direction: .older))
        #expect(preserved.target.messageID == "selected")
        try await g.controller.commitNavigation(preserved)
        #expect(g.controller.snapshot?.committedOrdinal == 1)
        g.controller.stop()

        for localCount in [0, 1] {
            let h = try F(); let transition = SearchWriteBarrier()
            if localCount == 1 { try await h.seed([F.message("local-only", 2)]) }
            h.remote.pages = [.success(F.page([F.message("remote-only", 9)], exhausted: false)), .failure(.transientNetwork)]
            h.remote.gates[1] = transition
            h.controller.search(roomID: "room-1", keyword: "ㅋㅋ")
            try await h.continueAfterIdle(1)
            await transition.waitUntilSuspended()
            let initial = try #require(h.controller.snapshot?.identity)
            let chosen = try #require(try await h.controller.prepareNavigation(session: initial, direction: .older))
            try await h.controller.commitNavigation(chosen)
            await transition.release()
            try await F.until { h.controller.snapshot?.source == .localFallbackAfterServerFailure && h.controller.snapshot?.count == .completed(totalCount: localCount) }
            let replacement = try #require(h.controller.snapshot?.identity)
            let target = try await h.controller.prepareNavigation(session: replacement, direction: .older)
            #expect(target?.target.messageID == (localCount == 0 ? nil : "local-only"))
            #expect(h.controller.snapshot?.isLimited == true && h.remote.calls.count == 2)
            h.controller.stop()
        }
    }

    @Test func accessLossStopsSearchWithoutLocalBypass() async throws {
        for failure in [ChatSearchFailure.accessLost, .roomClosed] {
            let f = try F(); try await f.seed([F.message("private", 1)])
            f.remote.pages = [.failure(failure)]
            f.controller.search(roomID: "room-1", keyword: "ㅋㅋ")
            try await F.until { f.controller.snapshot?.count == .failed(failure) }
            #expect(f.controller.active == nil && f.local.opens == 0)
            f.controller.retry()
            #expect(f.remote.calls.count == 1)
        }
    }

    @Test func reconnectionWaitsForManualResearchAndPreservesLocalSelection() async throws {
        let f = try F(); f.network.online = false
        try await f.seed([F.message("local", 1)])
        f.controller.search(roomID: "room-1", keyword: "ㅋㅋ")
        try await f.completed(1)
        let id = try #require(f.controller.snapshot?.identity)
        let pending = try #require(try await f.controller.prepareNavigation(session: id, direction: .older))
        try await f.controller.commitNavigation(pending)
        f.network.online = true
        await Task.yield()
        #expect(f.remote.upperCalls == 0 && f.controller.snapshot?.selectedMessageID == "local")
        f.remote.pages = [.success(F.page([F.message("remote", 2), F.message("local", 1)]))]
        f.controller.search(roomID: "room-1", keyword: "ㅋㅋ")
        try await f.completed(2)
        #expect(f.remote.upperCalls == 1 && f.controller.snapshot?.identity != id && f.controller.snapshot?.isLimited == false)
        f.controller.stop()
    }
}
