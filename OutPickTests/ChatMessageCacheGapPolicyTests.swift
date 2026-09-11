import Foundation
import Testing
@testable import OutPick

struct ChatMessageCacheGapPolicyTests {
    private func message(_ seq: Int64, id: String? = nil) -> ChatMessage {
        ChatMessage(ID: id ?? "m\(seq)", seq: seq, roomID: "room", senderUID: "user",
            senderNickname: "사용자", msg: "본문", sentAt: nil, attachments: [], replyPreview: nil)
    }

    @Test func completeCacheAndFragmentedRecovery() throws {
        let request = try ChatMessagePageRequest(roomID: "room", direction: .older, boundarySeq: 201, upperSeq: 200)
        let all = (Int64(101)...200).map { message($0) }
        #expect(ChatMessageCacheGapPolicy.recoveryRanges(for: request, messages: all).isEmpty)
        let two = all.filter { !(150...152).contains($0.seq) && $0.seq != 180 }
        #expect(ChatMessageCacheGapPolicy.recoveryRanges(for: request, messages: two) == [
            ChatMessageSequenceRange(lower: 150, upper: 152)!, ChatMessageSequenceRange(lower: 180, upper: 180)!
        ])
        let three = all.filter { ![120, 150, 180].contains($0.seq) }
        #expect(ChatMessageCacheGapPolicy.recoveryRanges(for: request, messages: three) == [request.range!])
    }

    @Test func partialOlderPageStopsAtGapEvenWithEnoughRowsOutsideRange() throws {
        let request = try ChatMessagePageRequest(roomID: "room", direction: .older, boundarySeq: 201, upperSeq: 200)
        let rows = (Int64(100)...200).filter { $0 != 150 }.map { message($0) }
        let result = try ChatMessageCacheGapPolicy.result(for: request, messages: rows)
        #expect(result.contiguousMessages.map(\.seq) == Array(Int64(151)...200))
        #expect(result.nextBoundarySeq == 151)
        #expect(!result.isComplete)
    }

    @Test func newerDirectionAndIntegerEdges() throws {
        let request = try ChatMessagePageRequest(roomID: "room", direction: .newer, boundarySeq: 100, upperSeq: 104)
        let result = try ChatMessageCacheGapPolicy.result(for: request, messages: [message(101), message(103), message(104)])
        #expect(result.nextBoundarySeq == 101)
        let end = try ChatMessagePageRequest(roomID: "room", direction: .newer, boundarySeq: .max, upperSeq: .max)
        #expect(end.range == nil)
        let last = try ChatMessagePageRequest(roomID: "room", direction: .newer, boundarySeq: Int64.max - 1, upperSeq: .max)
        #expect(last.range?.upper == Int64.max)
        let first = try ChatMessagePageRequest(roomID: "room", direction: .older, boundarySeq: 1, upperSeq: 200)
        #expect(first.range == nil)
    }

    @Test func deletedMessagesCountAndIdentityConflictsFail() throws {
        var deleted = message(150)
        deleted.isDeleted = true
        deleted.deletionRevision = 1
        #expect(try ChatMessageMergePolicy.preferred(deleted, message(150)).isDeleted)
        #expect(throws: ChatMessagePageError.identityConflict) {
            try ChatMessageMergePolicy.merge([message(150), message(150, id: "other")], roomID: "room")
        }
        let request = try ChatMessagePageRequest(roomID: "room", direction: .older, boundarySeq: 151, limit: 1, upperSeq: 200)
        #expect(try ChatMessageCacheGapPolicy.result(for: request, messages: [deleted]).isComplete)
    }
}
