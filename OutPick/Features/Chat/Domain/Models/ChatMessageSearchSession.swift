import Foundation

/// UI와 저장소가 함께 검사하는 수명 토큰. 계정 재로그인도 다른 epoch다.
struct ChatSearchSessionIdentity: Hashable, Sendable {
    let sessionID: UUID
    let accountID: String
    let accountEpoch: UUID
    let roomID: String
    let generation: UInt64
}

struct ChatSearchScope: Equatable, Sendable {
    let identity: ChatSearchSessionIdentity
    let normalizedQuery: String
    let upperSeq: Int64
    let source: ChatMessageSearchSource

    init(identity: ChatSearchSessionIdentity, keyword: String, upperSeq: Int64, source: ChatMessageSearchSource) throws {
        let normalized = ChatMessageSearchIndex.normalize(keyword)
        guard !normalized.isEmpty, upperSeq >= 0,
              !identity.accountID.isEmpty, !identity.roomID.isEmpty else {
            throw ChatSearchFailure.invalidRequest
        }
        self.identity = identity
        self.normalizedQuery = normalized
        self.upperSeq = upperSeq
        self.source = source
    }
}

/// Firebase 객체와 정렬 tuple은 Repository 내부에서만 해석한다.
struct ChatSearchCursor: Equatable, Sendable {
    let opaqueValue: Data
}

struct ChatSearchResultMetadata: Equatable, Sendable {
    let messageID: String
    let seq: Int64
    let senderUID: String
}

enum ChatSearchFailure: Error, Equatable, Sendable {
    case transientNetwork
    case accessLost
    case roomClosed
    case invalidRequest
    case indexConfiguration
    case malformedData
    case incompatibleIndexVersion
    case localStorage
}

enum ChatSearchCountState: Equatable, Sendable {
    case unknown
    case scanning(knownCount: Int)
    case completed(totalCount: Int)
    case failed(ChatSearchFailure)
}

struct ChatSearchSessionSnapshot: Equatable, Sendable {
    let identity: ChatSearchSessionIdentity
    let source: ChatMessageSearchSource
    let visibilityRevision: UInt64
    let count: ChatSearchCountState
    let selectedMessageID: String?
    let committedOrdinal: Int?
    var isRefreshing: Bool = false
    var isPaused: Bool = false
    var isFetching: Bool = false

    var isLimited: Bool { source != .serverIndex }
}

enum ChatSearchDirection: Sendable {
    case older
    case newer
}

/// 실제 화면 이동 성공 후 동일 토큰을 commit해야 순번이 바뀐다.
struct ChatSearchPendingNavigation: Equatable, Sendable {
    let identity: ChatSearchSessionIdentity
    let navigationGeneration: UInt64
    let visibilityRevision: UInt64
    let target: ChatSearchResultMetadata
}
