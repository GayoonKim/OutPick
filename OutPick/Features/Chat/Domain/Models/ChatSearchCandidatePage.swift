import Foundation

struct ChatSearchCandidatePage {
    /// 전체 검색어의 포함 판정 전 원본 후보다. 빈 일치 페이지도 커서를 진행한다.
    let candidates: [ChatMessage]
    let nextCursor: ChatSearchCursor?
    let isExhausted: Bool
}

protocol ChatSearchCandidateReading {
    func fetchSearchUpperSequence(roomID: String) async throws -> Int64
    func fetchSearchCandidatePage(scope: ChatSearchScope, after: ChatSearchCursor?, limit: Int) async throws -> ChatSearchCandidatePage
}
