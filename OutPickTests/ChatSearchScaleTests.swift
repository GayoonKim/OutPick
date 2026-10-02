import Foundation
import Darwin
import GRDB
import Testing
@testable import OutPick

/// 실제 검색 엔진/GRDB를 사용한다. 입력·기대값·관측값 모두 전체 결과 배열을 만들지 않는다.
@MainActor struct ChatSearchScaleTests {
    @Test func streamedScenariosPreserveReferenceCountsBoundsAndCleanup() async throws {
        for size in [10_000, 100_000, 1_000_000] {
            for distribution in ScaleDistribution.allCases {
                try await run(size: size, distribution: distribution)
            }
        }
        try await cancelDuringPage()
    }

    private func run(size: Int, distribution: ScaleDistribution) async throws {
        print("SEARCH_SCALE_BEGIN size=\(size) distribution=\(distribution.rawValue)")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OutPick-Search-Scale-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("search.sqlite").path
        let database = try AppDatabase(path: path)
        defer {
            do {
                try database.dbPool.close()
                try FileManager.default.removeItem(at: directory)
            } catch { Issue.record(error) }
        }
        let store = SearchStoreSpy(base: GRDBChatSearchStore(database: database))
        if distribution == .mixed {
            // 삭제 marker는 session과 독립된 기존 DB 경계를 통과하도록 미리 만든다.
            for start in stride(from: 13, through: size, by: 13_000) {
                try await database.dbPool.write { db in
                    for seq in stride(from: start, through: min(start + 12_987, size), by: 13) {
                        try db.execute(sql: """
                            INSERT INTO chatDeletedMessageMarker(accountID, roomID, messageID, revision, deletedAt)
                            VALUES ('account-1', 'room-1', ?, ?, NULL)
                            """, arguments: ["scale-\(seq)", seq])
                    }
                }
            }
        }
        let reference = distribution.reference(size: size)
        let source = ScalePageSource(size: size, distribution: distribution)
        let visibility = UserBlockVisibilityStore()
        visibility.beginSession(accountID: "account-1", cachedIDs: distribution == .mixed ? ["blocked"] : [])
        let engine = ChatSearchSessionController(remote: source,
            local: SearchLocalSpy(base: GRDBChatSearchLocalReader(database: database)),
            store: store, visibility: visibility, validation: SearchValidationFake(),
            network: SearchNetworkFake(), deletionFence: ChatSearchDeletionFence())
        let memory = ScaleMemorySampler()
        memory.start()
        defer { _ = memory.stop() }
        let start = ProcessInfo.processInfo.systemUptime
        var firstHitSeconds: Double?
        var completionSeconds: Double?
        var finished = false
        let observer = engine.observe { value in
            guard let value else { return }
            switch value.count {
            case .scanning(let count), .completed(let count):
                if count > 0, firstHitSeconds == nil { firstHitSeconds = ProcessInfo.processInfo.systemUptime - start }
            default: break
            }
            if case .completed = value.count {
                completionSeconds = ProcessInfo.processInfo.systemUptime - start
                finished = true
            }
            if case .failed = value.count { finished = true }
        }
        engine.search(roomID: "room-1", keyword: distribution.keyword)
        while engine.active?.task != nil {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let initialDemandSeconds = ProcessInfo.processInfo.systemUptime - start
        let initialCandidates = source.documents
        let initialPages = source.calls
        #expect(initialCandidates <= 500 && initialPages <= 5)
        if distribution == .frequent || distribution == .mixed || distribution == .sparse {
            #expect(initialPages == 1)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let idleExtraRequests = source.calls - initialPages
        #expect(source.calls == initialPages && source.documents == initialCandidates)
        var demandStartPage = source.calls
        var explicitDemands = 0
        // 전량 reference 검증은 사용자의 반복적인 계속 찾기를 테스트가 명시적으로 대행한다.
        while !finished {
            try Task.checkCancellation()
            if let snapshot = engine.snapshot, !snapshot.isFetching, !snapshot.isRefreshing, engine.active?.task == nil {
                #expect(source.calls - demandStartPage <= 5)
                demandStartPage = source.calls
                explicitDemands += 1
                engine.continueSearch(session: snapshot.identity)
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(source.calls - demandStartPage <= 5)
        let measured = memory.stop()
        defer { engine.removeObserver(observer); engine.stop() }
        let snapshot = try #require(engine.snapshot)
        #expect(snapshot.count == .completed(totalCount: reference.count))
        #expect(source.calls == max(1, (reference.candidates + 99) / 100))
        #expect(source.documents == reference.candidates)
        #expect(source.repeatedOrInvalidCursor == 0)
        #expect(source.maximumInFlight == 1)
        #expect(source.maximumPage <= 100)
        #expect(store.maximumHitPage <= 100)
        #expect(measured.baseline > 0 && measured.peak >= measured.baseline)

        // DB cursor로 최종 결과 전체를 독립적으로 순회해 순서·ID·작성자·hash를 검증한다.
        let identity = snapshot.identity
        let actual = try await database.dbPool.read { db -> ScaleReference in
            let cursor = try Row.fetchCursor(db, sql: """
                SELECT messageID, seq, senderUID FROM chatSearchHit
                WHERE sessionID = ? ORDER BY seq DESC, messageID DESC
                """, arguments: [identity.sessionID.uuidString])
            var result = ScaleReference()
            var previous = Int64.max
            while let row = try cursor.next() {
                let seq: Int64 = row["seq"]
                let id: String = row["messageID"]
                let author: String = row["senderUID"]
                guard seq < previous, id == "scale-\(seq)", author == "author" else {
                    throw ScaleFailure.invalidResult
                }
                previous = seq
                result.append(seq)
            }
            return result
        }
        #expect(actual.count == reference.count)
        #expect(actual.hash == reference.hash)
        #expect(actual.first == reference.first && actual.last == reference.last)
        let firstPage = try await store.results(identity: identity, offset: 0, limit: 100)
        #expect(firstPage.count == min(100, reference.count))
        if let last = reference.last {
            let finalPage = try await store.results(identity: identity, offset: reference.count - 1, limit: 100)
            #expect(finalPage.map(\.seq) == [last])
            let ordinal = try await store.ordinal(identity: identity, messageID: "scale-\(last)")
            #expect(ordinal == reference.count)
        }
        #expect(store.maximumResultPage <= 100)
        let fileSizes = try ["", "-wal", "-shm"].reduce(Int64(0)) { total, suffix in
            let file = path + suffix
            guard FileManager.default.fileExists(atPath: file) else { return total }
            let bytes = ((try FileManager.default.attributesOfItem(atPath: file)[.size]) as? NSNumber)?.int64Value ?? 0
            return total + bytes
        }
        let allocatedBytes = try await database.dbPool.read { db in
            (try Int64.fetchOne(db, sql: "PRAGMA page_count") ?? 0) * (try Int64.fetchOne(db, sql: "PRAGMA page_size") ?? 0)
        }
        let cleanupStart = ProcessInfo.processInfo.systemUptime
        engine.stop()
        try await store.closeSession(identity: identity)
        let residue = try await searchResidue(database)
        #expect(residue == 0)
        let cleanupSeconds = ProcessInfo.processInfo.systemUptime - cleanupStart
        let report: [String: Any] = [
            "size": size, "distribution": distribution.rawValue, "matches": actual.count,
            "initialDemandSeconds": initialDemandSeconds, "initialCandidateDocuments": initialCandidates,
            "initialCandidatePages": initialPages, "idleExtraRequests": idleExtraRequests,
            "explicitContinueDemands": explicitDemands, "completionMode": "explicitRepeatedDemand",
            "firstHitSeconds": firstHitSeconds.map { $0 as Any } ?? NSNull(),
            "completionSeconds": completionSeconds.map { $0 as Any } ?? NSNull(),
            "actualDisplaySeconds": NSNull(), "candidateDocuments": source.documents,
            "candidatePages": source.calls, "maxInFlight": source.maximumInFlight,
            "maxRawPage": source.maximumPage, "maxHitPage": store.maximumHitPage,
            "maxResultPage": store.maximumResultPage, "duplicateCursor": source.repeatedOrInvalidCursor,
            "baselineFootprintBytes": measured.baseline, "sampledPeakFootprintBytes": measured.peak,
            "databaseFilesBytes": fileSizes, "allocatedDatabaseBytes": allocatedBytes,
            "cleanupSeconds": cleanupSeconds, "cleanupResidue": residue, "referenceHash": String(reference.hash)
        ]
        print("SEARCH_SCALE_RESULT " + String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
    }

    private func cancelDuringPage() async throws {
        let database = try TemporaryAppDatabase.make()
        let source = ScalePageSource(size: 1_000_000, distribution: .frequent)
        let gate = SearchWriteBarrier()
        source.gateAtCall = 11; source.gate = gate
        let store = SearchStoreSpy(base: GRDBChatSearchStore(database: database))
        let visibility = UserBlockVisibilityStore()
        visibility.beginSession(accountID: "account-1", cachedIDs: [])
        let engine = ChatSearchSessionController(remote: source,
            local: SearchLocalSpy(base: GRDBChatSearchLocalReader(database: database)), store: store,
            visibility: visibility, validation: SearchValidationFake(), network: SearchNetworkFake(),
            deletionFence: ChatSearchDeletionFence())
        engine.search(roomID: "room-1", keyword: "ㅋㅋ")
        for _ in 0..<10 {
            try await SearchSessionFixture.until { engine.active?.task == nil }
            engine.continueSearch(session: try #require(engine.snapshot?.identity))
        }
        await gate.waitUntilSuspended()
        let identity = try #require(engine.snapshot?.identity)
        let worker = engine.active?.task
        let beforeCalls = source.calls
        let beforeCommits = store.commits
        engine.stop()
        await gate.release()
        await worker?.value
        try await store.closeSession(identity: identity)
        let residue = try await searchResidue(database)
        #expect(source.calls == beforeCalls)
        #expect(store.commits == beforeCommits)
        #expect(engine.snapshot == nil)
        #expect(residue == 0)
        print("SEARCH_SCALE_CANCEL requestsAfterCancel=\(source.calls - beforeCalls) commitsAfterCancel=\(store.commits - beforeCommits) residue=\(residue)")
    }

    private func searchResidue(_ database: AppDatabase) async throws -> Int {
        try await database.dbPool.read { db in
            try ["chatSearchSession", "chatSearchHit", "chatSearchBlockedAuthor"].reduce(0) {
                $0 + (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($1)") ?? 0)
            }
        }
    }
}

private enum ScaleFailure: Error { case invalidResult }

private struct ScaleReference {
    var count = 0
    var candidates = 0
    var hash: UInt64 = 14695981039346656037
    var first: Int64?
    var last: Int64?
    mutating func append(_ seq: Int64) {
        count += 1; first = first ?? seq; last = seq
        hash = (hash ^ UInt64(seq)) &* 1099511628211
    }
}

private enum ScaleDistribution: String, CaseIterable {
    case sparse, frequent, prefixCollision, oldestOnly, none, mixed
    var keyword: String {
        switch self {
        case .prefixCollision, .oldestOnly, .none: return "ㅋㅋ목표"
        default: return "ㅋㅋ"
        }
    }
    func text(_ seq: Int) -> String {
        switch self {
        case .sparse: return seq % 997 == 0 ? "뭐야 ㅋㅋ" : "일반 대화"
        case .frequent, .mixed: return seq % 2 == 0 ? "ㅋㅋㅋㅋㅋ" : "뭐야 ㅋㅋ"
        case .prefixCollision: return seq % 997 == 0 ? "앞 ㅋㅋ목표 뒤" : "ㅋㅋ다른"
        case .oldestOnly: return seq == 1 ? "앞 ㅋㅋ목표 뒤" : "ㅋㅋ다른"
        case .none: return "ㅋㅋ다른"
        }
    }
    func reference(size: Int) -> ScaleReference {
        var result = ScaleReference()
        for seq in stride(from: size, through: 1, by: -1) {
            // 검색 helper를 호출하지 않는 산술 기대값으로 생성 규칙과 대조한다.
            if self != .sparse || seq % 997 == 0 { result.candidates += 1 }
            let matched: Bool
            switch self {
            case .sparse, .prefixCollision: matched = seq % 997 == 0
            case .frequent: matched = true
            case .oldestOnly: matched = seq == 1
            case .none: matched = false
            case .mixed: matched = seq % 7 != 0 && seq % 11 != 0 && seq % 13 != 0
            }
            if matched { result.append(Int64(seq)) }
        }
        return result
    }
}

@MainActor private final class ScalePageSource: ChatSearchCandidateReading {
    let size: Int
    let distribution: ScaleDistribution
    var calls = 0
    var documents = 0
    var maximumInFlight = 0
    var maximumPage = 0
    var repeatedOrInvalidCursor = 0
    var gateAtCall: Int?
    var gate: SearchWriteBarrier?
    private var inFlight = 0
    private var next: Int
    private var lastCursor: ChatSearchCursor?
    private var lastLog = ProcessInfo.processInfo.systemUptime
    init(size: Int, distribution: ScaleDistribution) {
        self.size = size; self.distribution = distribution; next = size
    }
    func fetchSearchUpperSequence(roomID: String) async throws -> Int64 { Int64(size) }
    func fetchSearchCandidatePage(scope: ChatSearchScope, after: ChatSearchCursor?, limit: Int) async throws -> ChatSearchCandidatePage {
        if after != lastCursor { repeatedOrInvalidCursor += 1 }
        guard limit == 100, after == lastCursor else { throw ScaleFailure.invalidResult }
        calls += 1; inFlight += 1; maximumInFlight = max(maximumInFlight, inFlight)
        defer { inFlight -= 1 }
        if calls == gateAtCall, let gate { await gate.suspend() }
        var messages: [ChatMessage] = []
        while next > 0, messages.count < limit {
            let seq = next; next -= 1
            if distribution == .sparse, seq % 997 != 0 { continue }
            var message = GRDBTestFixtures.message(id: "scale-\(seq)", seq: Int64(seq),
                senderUID: distribution == .mixed && seq % 7 == 0 ? "blocked" : "author",
                text: distribution.text(seq))
            if distribution == .mixed, seq % 11 == 0 { message.isDeleted = true }
            messages.append(message)
        }
        // 후보가 희소한 경우 마지막 전달 뒤 남은 비후보 범위를 소진한다.
        if distribution == .sparse, next < 997 { next = 0 }
        documents += messages.count; maximumPage = max(maximumPage, messages.count)
        let cursor = ChatSearchCursor(opaqueValue: Data(String(next).utf8))
        lastCursor = cursor
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastLog >= 20 {
            print("SEARCH_SCALE_PROGRESS size=\(size) distribution=\(distribution.rawValue) candidates=\(documents) pages=\(calls)")
            lastLog = now
        }
        return ChatSearchCandidatePage(candidates: messages, nextCursor: cursor, isExhausted: next == 0)
    }
}

/// 20ms 간격 프로세스 footprint 표본 최대값. UI 표시 시간·실기기 RSS로 해석하지 않는다.
private final class ScaleMemorySampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "outpick.search.scale.memory")
    private var timer: DispatchSourceTimer?
    private var baseline: UInt64 = 0
    private var peak: UInt64 = 0
    func start() {
        queue.sync {
            baseline = Self.footprint(); peak = baseline
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(20))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.peak = max(self.peak, Self.footprint())
            }
            self.timer = timer; timer.resume()
        }
    }
    func stop() -> (baseline: UInt64, peak: UInt64) {
        queue.sync {
            timer?.cancel(); timer = nil
            peak = max(peak, Self.footprint())
            return (baseline, peak)
        }
    }
    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
