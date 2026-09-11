import Foundation

enum ChatMessageCacheGapPolicy {
    static func missingRanges(in range: ChatMessageSequenceRange, sequences: Set<Int64>) -> [ChatMessageSequenceRange] {
        var result: [ChatMessageSequenceRange] = []
        var start: Int64?
        var seq = range.lower
        while true {
            if sequences.contains(seq) {
                if let lower = start {
                    result.append(ChatMessageSequenceRange(lower: lower, upper: seq - 1)!)
                    start = nil
                }
            } else if start == nil {
                start = seq
            }
            if seq == range.upper { break }
            seq += 1
        }
        if let lower = start {
            result.append(ChatMessageSequenceRange(lower: lower, upper: range.upper)!)
        }
        return result
    }

    static func recoveryRanges(for request: ChatMessagePageRequest, messages: [ChatMessage]) -> [ChatMessageSequenceRange] {
        guard let range = request.range else { return [] }
        let sequences = Set(messages.filter { $0.roomID == request.roomID && $0.seq > 0 }.map(\.seq))
        let gaps = missingRanges(in: range, sequences: sequences)
        return gaps.count >= 3 ? [range] : gaps
    }

    static func result(for request: ChatMessagePageRequest, messages: [ChatMessage]) throws -> ChatMessagePageResult {
        guard let range = request.range else {
            return ChatMessagePageResult(messages: [], contiguousMessages: [],
                nextBoundarySeq: request.boundarySeq, unresolvedRanges: [])
        }
        let merged = try ChatMessageMergePolicy.merge(messages, roomID: request.roomID)
            .filter { range.contains($0.seq) }
        let bySeq = Dictionary(uniqueKeysWithValues: merged.map { ($0.seq, $0) })
        let gaps = missingRanges(in: range, sequences: Set(bySeq.keys))
        var contiguous: [ChatMessage] = []
        var seq = request.direction == .older ? range.upper : range.lower
        while let message = bySeq[seq] {
            contiguous.append(message)
            if request.direction == .older {
                if seq == range.lower { break }
                seq -= 1
            } else {
                if seq == range.upper { break }
                seq += 1
            }
        }
        let boundary = contiguous.last?.seq ?? request.boundarySeq
        return ChatMessagePageResult(messages: merged,
            contiguousMessages: contiguous.sorted { $0.seq < $1.seq },
            nextBoundarySeq: boundary, unresolvedRanges: gaps)
    }
}
