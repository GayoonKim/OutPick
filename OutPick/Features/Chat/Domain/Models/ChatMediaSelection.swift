import Foundation

struct ChatMediaPipelineLimits: Sendable {
    // iOS 15 지원 기기급에서 비교할 초기값. 이미지 decode/context와 파일 PUT은 별도 제한한다.
    var acquisition = 4
    // 실제 전송·스크롤 QA의 우선 비교 후보. 최종값은 2개와 동일 조건에서 비교 후 확정한다.
    var imagePreparation = 4
    let videoPreparation = 1
    var filesPerBatch = 4
}

struct ChatMediaSelection: Codable, Sendable {
    struct Source: Codable, Sendable {
        let index: Int
        let path: String
        let isVideo: Bool
    }
    struct PendingChunk: Codable, Sendable {
        let messageID: String
        let indices: [Int]
    }
    let selectionID: String
    let roomID: String
    let senderUID: String
    let createdAt: Date
    var selectionSources: [Source]
    var pendingChunk: PendingChunk?

    static func decode(_ record: ChatOutgoingOutboxRecord) -> Self? {
        guard let data = record.localPayloadJSON?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}
