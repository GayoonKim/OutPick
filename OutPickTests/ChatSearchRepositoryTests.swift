import Foundation
import FirebaseFirestore
import Testing
@testable import OutPick

struct ChatSearchRepositoryTests {
    @Test func queryUsesBoundedLimitUpperSequenceAndExclusiveRawCursor() async throws {
        let fake = SearchTransportFake()
        let repo = FirebaseChatSearchRepository(transport: fake)
        #expect(try await repo.fetchSearchUpperSequence(roomID: "r") == 10)
        let scope = try makeScope("ㅋㅋ정답")
        fake.page = response([document("z", 10, "ㅋㅋ불일치"), document("a", 10, "ㅋㅋ다른 후보")])
        let first = try await repo.fetchSearchCandidatePage(scope: scope, after: nil, limit: 2)
        #expect(!first.isExhausted)
        #expect(first.candidates.count == 2)
        #expect(first.candidates.allSatisfy { !ChatMessageSearchIndex.contains($0.msg, keyword: scope.normalizedQuery) })
        #expect(fake.queries.first == FirebaseChatSearchQuery(roomID: "r", tokenField: "searchNgrams2", token: "ㅋㅋ", upperSeq: 10, after: nil, limit: 2))
        fake.page = response([document("old", 1, "오래된 ㅋㅋ정답")])
        let second = try await repo.fetchSearchCandidatePage(scope: scope, after: first.nextCursor, limit: 2)
        #expect(second.isExhausted)
        #expect(second.candidates.map(\.ID) == ["old"])
        #expect(fake.queries.last?.after == FirebaseChatSearchBoundary(seq: 10, documentID: "a"))
        #expect(fake.roomReads == 1) // 커서 문서나 방 상한을 다시 읽지 않는다.
        fake.page = response([])
        let empty = try await repo.fetchSearchCandidatePage(scope: scope, after: second.nextCursor, limit: 2)
        #expect(empty.isExhausted && empty.candidates.isEmpty)
        #expect(empty.nextCursor == second.nextCursor)
        for limit in [0, 101] {
            await #expect(throws: ChatSearchFailure.invalidRequest) { try await repo.fetchSearchCandidatePage(scope: scope, after: nil, limit: limit) }
        }
        let oldCursor = try #require(first.nextCursor)
        await #expect(throws: ChatSearchFailure.invalidRequest) { try await repo.fetchSearchCandidatePage(scope: makeScope("다른 검색"), after: oldCursor, limit: 2) }
        for rows in [[document("x", 11, "ㅋㅋ")], [document("x", 0, "ㅋㅋ")], [document("a", 2, "ㅋㅋ"), document("b", 2, "ㅋㅋ")], [document("x", 2, "ㅋㅋ"), document("x", 2, "ㅋㅋ")]] {
            fake.page = response(rows)
            await #expect(throws: ChatSearchFailure.malformedData) { try await repo.fetchSearchCandidatePage(scope: scope, after: nil, limit: 2) }
        }
    }

    @Test func serverOnlyPagesRejectCacheMalformedDataAndWrongIndexVersion() async throws {
        let fake = SearchTransportFake()
        let repo = FirebaseChatSearchRepository(transport: fake)
        let scope = try makeScope("ㅋㅋ")
        for (cached, pending) in [(true, false), (false, true)] {
            fake.page = FirebaseChatSearchSnapshot(documents: [document("a", 1, "ㅋㅋ")], isFromCache: cached, hasPendingWrites: pending)
            await #expect(throws: ChatSearchFailure.transientNetwork) { try await repo.fetchSearchCandidatePage(scope: scope, after: nil, limit: 100) }
            fake.room = fake.page
            await #expect(throws: ChatSearchFailure.transientNetwork) { try await repo.fetchSearchUpperSequence(roomID: "r") }
        }
        let valid = document("a", 1, "ㅋㅋ")
        for value in [1, "2", true] as [Any] {
            var data = valid.data; data["searchIndexVersion"] = value
            fake.page = response([FirebaseChatSearchDocument(id: "a", data: data)])
            await #expect(throws: ChatSearchFailure.incompatibleIndexVersion) { try await repo.fetchSearchCandidatePage(scope: scope, after: nil, limit: 100) }
        }
        for (key, value) in [("seq", 1.5 as Any), ("seq", true as Any), ("seq", Double.infinity as Any), ("msg", 123 as Any), ("senderUID", "" as Any), ("searchNormalized", "wrong" as Any), ("searchNgrams2", [] as Any), ("sentAt", "invalid" as Any), ("roomID", "other" as Any), ("roomID", 123 as Any), ("ID", true as Any)] {
            var data = valid.data; data[key] = value
            fake.page = response([FirebaseChatSearchDocument(id: "a", data: data)])
            await #expect(throws: ChatSearchFailure.malformedData) { try await repo.fetchSearchCandidatePage(scope: scope, after: nil, limit: 100) }
        }
        for (code, expected) in [(FirestoreErrorCode.Code.permissionDenied, ChatSearchFailure.accessLost), (.unauthenticated, .accessLost), (.unavailable, .transientNetwork), (.failedPrecondition, .indexConfiguration), (.invalidArgument, .invalidRequest)] {
            fake.error = NSError(domain: FirestoreErrorDomain, code: code.rawValue)
            await #expect(throws: expected) { try await repo.fetchSearchCandidatePage(scope: scope, after: nil, limit: 100) }
        }
        fake.error = CancellationError()
        await #expect(throws: CancellationError.self) { try await repo.fetchSearchCandidatePage(scope: scope, after: nil, limit: 100) }
        fake.error = nil
        fake.room = response([])
        await #expect(throws: ChatSearchFailure.roomClosed) { try await repo.fetchSearchUpperSequence(roomID: "r") }
        fake.room = response([FirebaseChatSearchDocument(id: "r", data: ["seq": 10, "isClosed": true])])
        await #expect(throws: ChatSearchFailure.roomClosed) { try await repo.fetchSearchUpperSequence(roomID: "r") }
    }

    private func makeScope(_ keyword: String) throws -> ChatSearchScope {
        try ChatSearchScope(identity: ChatSearchSessionIdentity(sessionID: UUID(), accountID: "u", accountEpoch: UUID(), roomID: "r", generation: 1), keyword: keyword, upperSeq: 10, source: .serverIndex)
    }

    private func document(_ id: String, _ seq: Int64, _ text: String) -> FirebaseChatSearchDocument {
        let fields = ChatMessageSearchIndex.buildIndexedFields(from: text)
        return FirebaseChatSearchDocument(id: id, data: [
            "ID": id, "roomID": "r", "seq": seq, "msg": text, "senderUID": "sender", "messageType": "Text", "sentAt": "2026-10-02T00:00:00Z",
            "searchNormalized": fields.normalizedText, "searchChars": fields.searchChars, "searchNgrams2": fields.searchNgrams2, "searchIndexVersion": fields.version
        ])
    }
}

private func response(_ documents: [FirebaseChatSearchDocument]) -> FirebaseChatSearchSnapshot {
    FirebaseChatSearchSnapshot(documents: documents, isFromCache: false, hasPendingWrites: false)
}

private final class SearchTransportFake: FirebaseChatSearchTransport {
    var room = response([FirebaseChatSearchDocument(id: "r", data: ["seq": 10, "lifecycleStatus": "active"])])
    var page = response([])
    var error: Error?
    var queries: [FirebaseChatSearchQuery] = []
    var roomReads = 0
    func roomFromServer(roomID: String) async throws -> FirebaseChatSearchSnapshot {
        roomReads += 1
        if let error { throw error }
        return room
    }
    func candidatesFromServer(query: FirebaseChatSearchQuery) async throws -> FirebaseChatSearchSnapshot {
        queries.append(query)
        if let error { throw error }
        return page
    }
}
