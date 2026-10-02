import Foundation
import GRDB
import Testing
@testable import OutPick

struct GRDBChatSearchStoreTests {
    private typealias F = SearchStoreFixture

    @Test func failedPageCommitRollsBackHitsAndCursor() async throws {
        let database = try TemporaryAppDatabase.make()
        let store = GRDBChatSearchStore(database: database)
        let scope = try F.scope()
        try await store.createSession(scope: scope, visibilityRevision: 0, blockedAuthorIDs: [])
        for event in ["BEFORE INSERT ON chatSearchHit WHEN NEW.messageID = 'second'", "BEFORE UPDATE OF rawCursor ON chatSearchSession"] {
            try await F.fail(database, on: event)
            await #expect(throws: (any Error).self) {
                try await F.commit(store, scope, hits: [F.hit("first", 2), F.hit("second", 1)])
            }
            #expect(try await store.state(identity: scope.identity) == ChatSearchStoredState(cursor: nil, isExhausted: false, visibilityRevision: 0, count: 0))
            try await F.clearFailure(database)
        }
        let saved = try await F.commit(store, scope, hits: [F.hit("first", 2), F.hit("second", 1)])
        #expect(saved.count == 2)
        await #expect(throws: ChatSearchPersistenceError.cursorChanged) { try await F.commit(store, scope, hits: [F.hit("first", 2)]) }
        let final = try await F.commit(store, scope, hits: [F.hit("first", 2)], after: saved.cursor, next: "end", exhausted: true)
        #expect(final.count == 2 && final.isExhausted)
    }

    @Test func generalMessagePruningPreservesSearchHits() async throws {
        let database = try TemporaryAppDatabase.make()
        let search = GRDBChatSearchStore(database: database)
        let messages = GRDBChatMessageStore(database: database)
        let scope = try F.scope()
        try await search.createSession(scope: scope, visibilityRevision: 0, blockedAuthorIDs: [])
        _ = try await F.commit(search, scope, hits: [F.hit("m1", 1)])
        // 현재 캐시는 3,300개 초과 시 3,000개로 정리한다.
        try await messages.saveChatMessages((1...3301).map { GRDBTestFixtures.message(id: "m\($0)", seq: Int64($0)) })
        let remaining = try await database.dbPool.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chatMessage") }
        #expect(remaining == 3000)
        #expect(try await messages.fetchMessage(id: "m1", inRoom: "room-1") == nil)
        #expect(try await search.results(identity: scope.identity, offset: 0, limit: 1) == [F.hit("m1", 1)])
        #expect(try await search.ordinal(identity: scope.identity, messageID: "m1") == 1)
        // 이동에 필요한 ID/seq가 남는다. 실제 원격 주변 대화·화면 이동은 Phase 5에서 검증한다.
    }

    @Test func cleanupRejectsLateWritesAcrossSessionRoomAndAccount() async throws {
        for mode in ["session", "room", "account"] {
            let database = try TemporaryAppDatabase.make()
            let search = GRDBChatSearchStore(database: database)
            let scope = try F.scope()
            let other = try F.scope(room: "other-room")
            try await search.createSession(scope: scope, visibilityRevision: 0, blockedAuthorIDs: ["blocked"])
            try await search.createSession(scope: other, visibilityRevision: 0, blockedAuthorIDs: [])
            try await GRDBChatMessageStore(database: database).saveChatMessages([GRDBTestFixtures.message(id: "unrelated", roomID: "other-room")])
            let gate = SearchWriteBarrier()
            let late = Task { await gate.suspend(); return try await F.commit(search, scope, hits: [F.hit("late", 1)]) }
            await gate.waitUntilSuspended()
            if mode == "session" { try await search.closeSession(identity: scope.identity) }
            if mode == "room" { try GRDBChatRoomLocalDataStore(database: database).cleanTransientRoomData(roomID: "room-1") }
            if mode == "account" { try await database.deleteAllUserSessionData() }
            await gate.release()
            await #expect(throws: ChatSearchPersistenceError.staleSession) { try await late.value }
            await #expect(throws: ChatSearchPersistenceError.staleSession) {
                try await search.applyVisibility(identity: scope.identity, revision: 1, blockedAuthorIDs: ["late-author"])
            }
            if mode != "account" {
                #expect(try await search.state(identity: other.identity).count == 0)
                #expect(try await GRDBChatMessageStore(database: database).fetchMessage(id: "unrelated", inRoom: "other-room") != nil)
            }
            let leftovers = try await database.dbPool.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chatSearchBlockedAuthor WHERE sessionID = ?", arguments: [scope.identity.sessionID.uuidString])
            }
            #expect(leftovers == 0)
        }
        let database = try TemporaryAppDatabase.make()
        let search = GRDBChatSearchStore(database: database)
        let scope = try F.scope()
        try await search.createSession(scope: scope, visibilityRevision: 0, blockedAuthorIDs: [])
        for id in [ChatSearchSessionIdentity(sessionID: scope.identity.sessionID, accountID: "other", accountEpoch: scope.identity.accountEpoch, roomID: "room-1", generation: 1),
                   ChatSearchSessionIdentity(sessionID: scope.identity.sessionID, accountID: "account-1", accountEpoch: UUID(), roomID: "room-1", generation: 1),
                   ChatSearchSessionIdentity(sessionID: scope.identity.sessionID, accountID: "account-1", accountEpoch: scope.identity.accountEpoch, roomID: "room-1", generation: 2)] {
            await #expect(throws: ChatSearchPersistenceError.staleSession) {
                try await search.commitPage(identity: id, visibilityRevision: 0, expectedCursor: nil, hits: [], nextCursor: F.cursor("next"), isExhausted: false)
            }
            try await search.closeSession(identity: id)
            #expect(try await search.state(identity: scope.identity).count == 0)
        }
    }

    @Test func migrationAndRestartRemoveOnlyTransientSearchData() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("search-migration-\(UUID()).sqlite").path
        let pool = try DatabasePool(path: path)
        try GRDBMigrationRegistry.makeMigrator().migrate(pool, upTo: "addMediaGenerationsToIndexes")
        let legacy = try AppDatabase(dbPool: pool, migrate: false)
        try await GRDBChatMessageStore(database: legacy).saveChatMessages([GRDBTestFixtures.message(id: "preserved")])
        let upgraded = try AppDatabase(dbPool: pool)
        let search = GRDBChatSearchStore(database: upgraded)
        let scope = try F.scope()
        try await search.createSession(scope: scope, visibilityRevision: 3, blockedAuthorIDs: ["blocked"])
        _ = try await F.commit(search, scope, hits: [F.hit("result", 1)], revision: 3)
        let restarted = try AppDatabase(dbPool: pool)
        #expect(try await GRDBChatMessageStore(database: restarted).fetchMessage(id: "preserved", inRoom: "room-1") != nil)
        try await pool.read { db in
            for table in ["chatSearchSession", "chatSearchHit", "chatSearchBlockedAuthor"] {
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)")
                #expect(count == 0)
            }
            let columns = try db.columns(in: "chatSearchHit").map(\.name)
            #expect(columns == ["sessionID", "messageID", "seq", "senderUID"])
        }
    }

    @Test func resultWindowsAndDeletionEnumerationStayBounded() async throws {
        let database = try TemporaryAppDatabase.make()
        let search = GRDBChatSearchStore(database: database)
        let deletion = GRDBChatDeletionSyncStore(database: database)
        let scope = try F.scope()
        try await search.createSession(scope: scope, visibilityRevision: 0, blockedAuthorIDs: [])
        var cursor: ChatSearchCursor?
        for start in stride(from: 1, through: 1003, by: 100) {
            let saved = try await F.commit(search, scope, hits: (start...min(start+99,1003)).map { F.hit(String(format: "m%04d", $0), Int64($0)) }, after: cursor, next: "\(start)")
            cursor = saved.cursor
        }
        #expect(try await search.results(identity: scope.identity, offset: 1000, limit: 100).map(\.seq) == [3,2,1])
        #expect(try await search.ordinal(identity: scope.identity, messageID: "m0001") == 1003)
        await #expect(throws: ChatSearchPersistenceError.invalidPage) { try await search.results(identity: scope.identity, offset: 0, limit: 101) }
        try await GRDBChatMessageStore(database: database).saveChatMessages([GRDBTestFixtures.message(id: "m0001")])
        var last: String?; var count = 0
        while true {
            let ids = try await deletion.messageIDs(accountID: "account-1", roomID: "room-1", afterID: last, limit: 100)
            #expect(ids.count <= 100)
            guard let next = ids.last else { break }
            #expect(last == nil || next > last!)
            count += ids.count; last = next
        }
        #expect(count == 1003)
        #expect(try await deletion.messageIDs(accountID: "other", roomID: "room-1", afterID: nil, limit: 100) == ["m0001"])
    }

    @Test func searchOnlyHitsParticipateInDeletionRecoveryAndDuplicateScrubbing() async throws {
        let database = try TemporaryAppDatabase.make()
        let search = GRDBChatSearchStore(database: database)
        let deletion = GRDBChatDeletionSyncStore(database: database)
        let scope = try F.scope()
        try await search.createSession(scope: scope, visibilityRevision: 0, blockedAuthorIDs: [])
        _ = try await F.commit(search, scope, hits: [F.hit("z",1),F.hit("a",2),F.hit("c",3)], exhausted: true)
        let rows = [F.delta("z",1),F.delta("a",2),F.delta("c",3)]
        let repository = SearchRecoveryRepository(head: 3, rows: rows)
        let useCase = ChatDeletionSyncUseCase(repository: repository, persistence: deletion, mediaCleaner: SearchNoopCleaner(), pageSize: 2)
        _ = try await useCase.reconcile(roomID: "room-1", accountID: "account-1", allowEmptyLocalBootstrap: true)
        #expect(await repository.pageQueries > 0)
        #expect(await repository.requestedIDs.allSatisfy { $0.count <= 2 })
        #expect(try await deletion.cursor(accountID: "account-1", roomID: "room-1") == 3)
        #expect(try await search.state(identity: scope.identity).count == 0)
        _ = try await deletion.recordResolvedDeletions(rows + rows, accountID: "account-1", roomID: "room-1")
        #expect(try await search.state(identity: scope.identity).count == 0)
        #expect(try await search.ordinal(identity: scope.identity, messageID: "z") == nil)

        let gapScope = try F.scope(account: "gap")
        try await search.createSession(scope: gapScope, visibilityRevision: 0, blockedAuthorIDs: [])
        _ = try await F.commit(search, gapScope, hits: [F.hit("missing",1)])
        let gap = ChatDeletionSyncUseCase(repository: SearchRecoveryRepository(head: 2, rows: []), persistence: deletion, mediaCleaner: SearchNoopCleaner())
        await #expect(throws: (any Error).self) { try await gap.reconcile(roomID: "room-1", accountID: "gap", allowEmptyLocalBootstrap: true) }
        #expect(try await deletion.cursor(accountID: "gap", roomID: "room-1") == 0)
    }

    @Test func deletionMarkerWinsAgainstLateCandidatePage() async throws {
        let database = try TemporaryAppDatabase.make()
        let search = GRDBChatSearchStore(database: database)
        let deletion = GRDBChatDeletionSyncStore(database: database)
        let scope = try F.scope()
        try await search.createSession(scope: scope, visibilityRevision: 0, blockedAuthorIDs: [])
        let gate = SearchWriteBarrier()
        let late = Task { await gate.suspend(); return try await F.commit(search, scope, hits: [F.hit("removed",1),F.hit("keep",2)]) }
        await gate.waitUntilSuspended()
        _ = try await deletion.apply([F.delta("removed",1)], accountID: "account-1", roomID: "room-1")
        await gate.release()
        #expect(try await late.value.count == 1)
        _ = try await deletion.apply([F.delta("keep",2)], accountID: "account-1", roomID: "room-1")
        #expect(try await search.state(identity: scope.identity).count == 0)
    }

    @Test func visibilityRevisionRejectsBothWriteOrdersAndRollsBackOnFailure() async throws {
        let database = try TemporaryAppDatabase.make()
        let search = GRDBChatSearchStore(database: database)
        let scope = try F.scope()
        try await search.createSession(scope: scope, visibilityRevision: 0, blockedAuthorIDs: [])
        let hits = [F.hit("blocked-hit",1,author:"blocked"),F.hit("valid",2)]
        let gate = SearchWriteBarrier()
        let late = Task { await gate.suspend(); return try await F.commit(search, scope, hits: hits) }
        await gate.waitUntilSuspended()
        _ = try await search.applyVisibility(identity: scope.identity, revision: 1, blockedAuthorIDs: ["blocked"])
        await gate.release()
        await #expect(throws: ChatSearchPersistenceError.visibilityChanged) { try await late.value }
        #expect(try await search.state(identity: scope.identity).cursor == nil)
        let page = try await F.commit(search, scope, hits: hits, revision: 1)
        #expect(page.count == 1 && page.insertedCount == 1)
        // 재조회에는 이번 삽입 수가 없고, rollback은 모든 영속 상태를 그대로 보존한다.
        var persistedPage = page
        persistedPage.insertedCount = 0
        for event in ["BEFORE INSERT ON chatSearchBlockedAuthor", "BEFORE DELETE ON chatSearchHit", "BEFORE UPDATE OF visibilityRevision ON chatSearchSession"] {
            try await F.fail(database, on: event)
            await #expect(throws: (any Error).self) {
                try await search.applyVisibility(identity: scope.identity, revision: 2, blockedAuthorIDs: ["author"])
            }
            #expect(try await search.state(identity: scope.identity) == persistedPage)
            #expect(try await search.results(identity: scope.identity, offset: 0, limit: 100).map(\.messageID) == ["valid"])
            let authors = try await database.dbPool.read { db in
                try String.fetchAll(db, sql: "SELECT senderUID FROM chatSearchBlockedAuthor WHERE sessionID = ?", arguments: [scope.identity.sessionID.uuidString])
            }
            #expect(authors == ["blocked"])
            try await F.clearFailure(database)
        }
        let removed = try await search.applyVisibility(identity: scope.identity, revision: 2, blockedAuthorIDs: ["author"])
        #expect(removed.count == 0 && removed.cursor == page.cursor)
        await #expect(throws: ChatSearchPersistenceError.visibilityChanged) { try await search.applyVisibility(identity: scope.identity, revision: 1, blockedAuthorIDs: []) }
        _ = try await search.applyVisibility(identity: scope.identity, revision: 3, blockedAuthorIDs: [])
        let retry = try await F.commit(search, scope, hits: hits, after: page.cursor, next: "end", revision: 3, exhausted: true)
        #expect(retry.count == 0) // 차단 해제는 새 검색에서만 복원한다.
    }
}
