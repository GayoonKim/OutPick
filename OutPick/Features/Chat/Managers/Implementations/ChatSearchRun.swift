import Foundation

/// 한 검색 세대의 작업과 최대 한 페이지를 소유한다. 전체 결과는 GRDB에만 둔다.
@MainActor final class ChatSearchRun {
    var identity: ChatSearchSessionIdentity
    let keyword: String
    var source: ChatMessageSearchSource
    var scope: ChatSearchScope?
    var upperBound: Int64?
    var retiredIdentity: ChatSearchSessionIdentity?
    var local: (any ChatSearchLocalSnapshot)?
    var pending: ChatSearchCandidatePage?
    var cursor: ChatSearchCursor?
    var exhausted = false
    // 예산은 명시적 수요에서만 채운다. 발행/foreground/자동 선택은 보충하지 않는다.
    var pagesRemaining = 5
    var created = false
    var needsValidation = true
    var shouldPublish = false
    var visibility: UserBlockVisibilitySnapshot
    var blockedAuthors: Set<String>
    var appliedVisibility: UInt64?
    var publicationRevision: UInt64 = 0
    var resultRevision: UInt64 = 0
    var failure: ChatSearchFailure?
    var task: Task<Void, Never>?
    var selected: ChatSearchResultMetadata?
    var replacementAnchor: ChatSearchResultMetadata?
    var preferredID: String?
    var waiters: [CheckedContinuation<Void, Never>] = []

    init(identity: ChatSearchSessionIdentity, keyword: String, source: ChatMessageSearchSource, visibility: UserBlockVisibilitySnapshot) {
        self.identity = identity; self.keyword = keyword; self.source = source; self.visibility = visibility
        blockedAuthors = visibility.blockedIDs
    }
    func wake() { let pending = waiters; waiters = []; pending.forEach { $0.resume() } }
}
