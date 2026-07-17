import Foundation

struct BannerPresentationQueueState {
    private struct OverflowSummary {
        var messageCount = 0
        var roomIDs = Set<String>()
        var latestPayload: BannerPayload?

        mutating func append(_ payload: BannerPayload) {
            messageCount += 1
            roomIDs.insert(payload.roomID)
            latestPayload = payload
        }

        mutating func takePayload() -> BannerPayload? {
            guard messageCount > 0, let latestPayload else { return nil }
            let title: String
            if roomIDs.count == 1 {
                title = "새 메시지 \(messageCount)개"
            } else {
                title = "\(roomIDs.count)개 채팅방의 새 메시지 \(messageCount)개"
            }
            let payload = BannerPayload(
                roomID: latestPayload.roomID,
                title: title,
                body: "\(latestPayload.title): \(latestPayload.body)",
                attachmentsCount: latestPayload.attachmentsCount
            )
            self = OverflowSummary()
            return payload
        }
    }

    private let outstandingHardCap: Int
    private(set) var current: BannerPayload?
    private(set) var pending: [BannerPayload] = []
    private var overflow = OverflowSummary()

    init(outstandingHardCap: Int = 5) {
        self.outstandingHardCap = max(1, outstandingHardCap)
    }

    mutating func enqueue(_ payload: BannerPayload) -> BannerPayload? {
        guard current != nil else {
            current = payload
            return payload
        }

        if 1 + pending.count < outstandingHardCap {
            pending.append(payload)
        } else {
            overflow.append(payload)
        }
        return nil
    }

    mutating func finishCurrent() -> BannerPayload? {
        current = nil
        if !pending.isEmpty {
            let next = pending.removeFirst()
            current = next
            return next
        }
        if let summary = overflow.takePayload() {
            current = summary
            return summary
        }
        return nil
    }

    mutating func reset() {
        current = nil
        pending.removeAll(keepingCapacity: false)
        overflow = OverflowSummary()
    }
}
