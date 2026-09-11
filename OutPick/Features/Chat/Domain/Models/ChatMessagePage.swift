import Foundation

enum ChatMessagePageDirection: Hashable, Sendable {
    case older
    case newer
}

struct ChatMessageSequenceRange: Hashable, Sendable {
    let lower: Int64
    let upper: Int64

    init?(lower: Int64, upper: Int64) {
        guard lower > 0, upper >= lower else { return nil }
        self.lower = lower
        self.upper = upper
    }

    func contains(_ seq: Int64) -> Bool { lower <= seq && seq <= upper }
}

struct ChatMessagePageRequest: Hashable, Sendable {
    let roomID: String
    let direction: ChatMessagePageDirection
    let boundarySeq: Int64
    let range: ChatMessageSequenceRange?

    init(roomID: String, direction: ChatMessagePageDirection, boundarySeq: Int64,
         limit: Int = 100, upperSeq: Int64) throws {
        guard !roomID.isEmpty, boundarySeq >= 0, upperSeq >= 0,
              limit > 0, limit <= 100 else { throw ChatMessagePageError.invalidRequest }
        self.roomID = roomID
        self.direction = direction
        self.boundarySeq = boundarySeq
        switch direction {
        case .older:
            range = boundarySeq > 1
                ? ChatMessageSequenceRange(lower: max(1, boundarySeq - Int64(limit)), upper: boundarySeq - 1)
                : nil
        case .newer:
            if boundarySeq < upperSeq {
                let remaining = upperSeq - boundarySeq
                range = ChatMessageSequenceRange(lower: boundarySeq + 1,
                    upper: boundarySeq + min(remaining, Int64(limit)))
            } else {
                range = nil
            }
        }
    }
}

enum ChatMessagePageError: Error, Equatable {
    case invalidRequest
    case invalidPayload
    case identityConflict
    case incomplete
}

struct ChatMessagePageResult: Sendable {
    var replacedMessageIDs: Set<String> = []
    /// 차단 필터 적용 전의 원본 메시지다. 화면 cursor는 이 결과로 계산한다.
    let messages: [ChatMessage]
    let contiguousMessages: [ChatMessage]
    let nextBoundarySeq: Int64
    let unresolvedRanges: [ChatMessageSequenceRange]
    var isComplete: Bool { unresolvedRanges.isEmpty }
}
