import Foundation
import Testing
@testable import OutPick

struct ChatMessagePageLoaderTests {
    @Test func twoRangesActuallyOverlap() async throws {
        let data = RangeData()
        let gate = RangeOverlapGate()
        let loader = ChatMessagePageLoader(local: { _, range in await data.local(range) }, remote: { _, range in
            await gate.arrive()
            return try await data.remote(range)
        })
        let request = try ChatMessagePageRequest(roomID: "room", direction: .older, boundarySeq: 201, upperSeq: 200)
        let result = try await loader.load(request)
        #expect(result.isComplete)
        #expect(await gate.arrivals == 2)
    }
    @Test func retryFetchesOnlyFailedRange() async throws {
        let data = RangeData(failAt: 180)
        let loader = ChatMessagePageLoader(local: { _, range in await data.local(range) },
            remote: { _, range in try await data.remote(range) })
        let request = try ChatMessagePageRequest(roomID: "room", direction: .older, boundarySeq: 201, upperSeq: 200)
        _ = try await loader.load(request)
        await data.allowRetry()
        let recovered = try await loader.load(request)
        #expect(recovered.isComplete)
        let queries = await data.queries
        #expect(queries.count == 3)
        #expect(queries.last == ChatMessageSequenceRange(lower: 180, upper: 180))
    }

    @Test func offlineAndInvalidRoomPayloadNeverAdvanceAcrossGap() async throws {
        let request = try ChatMessagePageRequest(roomID: "room", direction: .older, boundarySeq: 3, limit: 2, upperSeq: 2)
        let local = ChatMessage(ID: "m2", seq: 2, roomID: "room", senderUID: "user",
            senderNickname: "사용자", msg: "본문", sentAt: nil, attachments: [], replyPreview: nil)
        let wrong = ChatMessage(ID: "m1", seq: 1, roomID: "other", senderUID: "user",
            senderNickname: "사용자", msg: "본문", sentAt: nil, attachments: [], replyPreview: nil)
        for invalidPayload in [false, true] {
            let loader = ChatMessagePageLoader(local: { _, _ in [local] }, remote: { _, _ in
                if invalidPayload { return [wrong] }
                throw ChatMessagePageError.incomplete
            })
            let result = try await loader.load(request)
            #expect(!result.isComplete)
            #expect(result.nextBoundarySeq == 2)
            #expect(result.contiguousMessages.map(\.ID) == ["m2"])
        }
    }
    @Test func identityConflictRequiresCanonicalRangeBeforeReplacement() async throws {
        let canonical = ChatMessage(ID: "canonical", seq: 1, roomID: "room", senderUID: "user",
            senderNickname: "사용자", msg: "본문", sentAt: nil, attachments: [], replyPreview: nil)
        let stale = ChatMessage(ID: "stale", seq: 1, roomID: "room", senderUID: "user",
            senderNickname: "사용자", msg: "본문", sentAt: nil, attachments: [], replyPreview: nil)
        let loader = ChatMessagePageLoader(local: { _, _ in [canonical, stale] }, remote: { _, _ in [canonical] })
        let request = try ChatMessagePageRequest(roomID: "room", direction: .older, boundarySeq: 2, limit: 1, upperSeq: 1)
        let result = try await loader.load(request)
        #expect(result.isComplete)
        #expect(result.replacedMessageIDs == ["stale"])
        #expect(result.messages.map(\.ID) == ["canonical"])
    }
    @Test func twoGapsRecoverAndCompleteCacheDoesNotReadServer() async throws {
        let data = RangeData()
        let request = try ChatMessagePageRequest(roomID: "room", direction: .older, boundarySeq: 201, upperSeq: 200)
        let loader = ChatMessagePageLoader(local: { _, range in await data.local(range) },
            remote: { _, range in try await data.remote(range) })
        let first = try await loader.load(request)
        #expect(first.isComplete)
        #expect(first.contiguousMessages.count == 100)
        #expect(await data.queries.count == 2)
        await data.makeComplete()
        _ = try await loader.load(request)
        #expect(await data.queries.count == 2)
    }

    @Test func oneFailedRangeKeepsOtherSuccessAndStopsCursor() async throws {
        let data = RangeData(failAt: 180)
        let loader = ChatMessagePageLoader(local: { _, range in await data.local(range) },
            remote: { _, range in try await data.remote(range) })
        let request = try ChatMessagePageRequest(roomID: "room", direction: .older, boundarySeq: 201, upperSeq: 200)
        let result = try await loader.load(request)
        #expect(!result.isComplete)
        #expect(result.messages.contains { $0.seq == 150 })
        #expect(result.nextBoundarySeq == 181)
        #expect(result.unresolvedRanges == [ChatMessageSequenceRange(lower: 180, upper: 180)!])
    }
}

private actor RangeData {
    private var missing: Set<Int64> = [150, 180]
    private var failAt: Int64?
    private(set) var queries: [ChatMessageSequenceRange] = []
    init(failAt: Int64? = nil) { self.failAt = failAt }
    func makeComplete() { missing = [] }
    func allowRetry() { failAt = nil }
    func local(_ range: ChatMessageSequenceRange) -> [ChatMessage] {
        (range.lower...range.upper).filter { !missing.contains($0) }.map(message)
    }
    func remote(_ range: ChatMessageSequenceRange) throws -> [ChatMessage] {
        queries.append(range)
        if let failAt, range.contains(failAt) { throw ChatMessagePageError.incomplete }
        return (range.lower...range.upper).map(message)
    }
    private func message(_ seq: Int64) -> ChatMessage {
        ChatMessage(ID: "m\(seq)", seq: seq, roomID: "room", senderUID: "user",
            senderNickname: "사용자", msg: "본문", sentAt: nil, attachments: [], replyPreview: nil)
    }
}

private actor RangeOverlapGate {
    private(set) var arrivals = 0
    private var first: CheckedContinuation<Void, Never>?
    func arrive() async {
        arrivals += 1
        if arrivals == 1 {
            await withCheckedContinuation { first = $0 }
        } else {
            first?.resume()
            first = nil
        }
    }
}
