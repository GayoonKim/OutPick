import Foundation

enum ChatMessageMergePolicy {
    /// 화면의 프로필 overlay를 적용하기 전 서버 payload에서 사용한다.
    static func samePayload(_ lhs: ChatMessage, _ rhs: ChatMessage) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let left = try? encoder.encode(lhs), let right = try? encoder.encode(rhs) else { return false }
        return left == right
    }

    static func preferred(_ current: ChatMessage, _ incoming: ChatMessage) throws -> ChatMessage {
        guard current.roomID == incoming.roomID, current.ID == incoming.ID else {
            throw ChatMessagePageError.identityConflict
        }
        if current.seq > 0 && incoming.seq > 0 && current.seq != incoming.seq {
            throw ChatMessagePageError.identityConflict
        }
        if current.seq > 0 && incoming.seq <= 0 { return current }
        if current.seq <= 0 && incoming.seq > 0 { return incoming }
        if current.isDeleted || incoming.isDeleted {
            if current.isDeleted != incoming.isDeleted { return current.isDeleted ? current : incoming }
            let previousRevision = current.deletionRevision ?? 0
            let nextRevision = incoming.deletionRevision ?? 0
            if previousRevision != nextRevision { return previousRevision > nextRevision ? current : incoming }
            // 같은 revision의 작성자 표시 교정은 기존 서버 tombstone 계약을 따른다.
        }
        if current.roleEventSubjectIsRedacted == true && incoming.roleEventSubjectIsRedacted == false {
            return current
        }
        return incoming
    }

    static func merge(_ messages: [ChatMessage], roomID: String) throws -> [ChatMessage] {
        var byID: [String: ChatMessage] = [:]
        var idBySeq: [Int64: String] = [:]
        for message in messages {
            guard message.roomID == roomID, !message.ID.isEmpty, message.seq >= 0 else {
                throw ChatMessagePageError.invalidPayload
            }
            if message.seq > 0 {
                if let id = idBySeq[message.seq], id != message.ID { throw ChatMessagePageError.identityConflict }
                idBySeq[message.seq] = message.ID
            }
            byID[message.ID] = try byID[message.ID].map { try preferred($0, message) } ?? message
        }
        return byID.values.sorted {
            $0.seq == $1.seq ? $0.ID < $1.ID : $0.seq < $1.seq
        }
    }
}
