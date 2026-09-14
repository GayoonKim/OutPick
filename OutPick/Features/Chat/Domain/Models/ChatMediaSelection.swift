import Foundation

struct ChatMediaPipelineLimits: Sendable {
    // 원본 확보는 실기기 비교 후 4개를 유지한다. 파일 PUT과 별도로 제한한다.
    var acquisition = 4
    // 30장 묶음으로 나누기 전 연속 사진 구간 전체를 준비한다.
    var imagePreparation = Int.max
    let videoPreparation = 1
    var filesPerBatch = 4

    static func forCurrentProcess() -> Self {
        let environment = ProcessInfo.processInfo.environment
        let bundleIdentifier = Bundle.main.bundleIdentifier
        let limits = configured(environment: environment, bundleIdentifier: bundleIdentifier)
        #if DEBUG
        if bundleIdentifier == "GayoonKim.OutPick.dev", environment["OUTPICK_MEDIA_QA"] == "1" {
            print("[MediaQA] event=limits acquisition=\(limits.acquisition) uploads=\(limits.filesPerBatch) preparation=\(limits.imagePreparation)")
            ChatMediaQAMetrics.shared.start()
        }
        #endif
        return limits
    }

    static func configured(environment: [String: String], bundleIdentifier: String?) -> Self {
        var limits = Self()
        #if DEBUG
        if bundleIdentifier == "GayoonKim.OutPick.dev", environment["OUTPICK_MEDIA_QA"] == "1" {
            func width(_ value: String?, fallback: Int) -> Int {
                switch value {
                case "all": return Int.max
                case "4": return 4
                default: return fallback
                }
            }
            limits.acquisition = width(environment["OUTPICK_MEDIA_QA_ACQUISITION"], fallback: limits.acquisition)
            limits.imagePreparation = width(environment["OUTPICK_MEDIA_QA_PREPARATION"], fallback: limits.imagePreparation)
            limits.filesPerBatch = width(environment["OUTPICK_MEDIA_QA_UPLOADS"], fallback: limits.filesPerBatch)
        }
        #endif
        return limits
    }
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
