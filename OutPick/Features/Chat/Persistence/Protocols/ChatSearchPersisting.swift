import Foundation

enum ChatSearchPersistenceError: Error, Equatable {
    case staleSession
    case visibilityChanged
    case cursorChanged
    case invalidPage
}

struct ChatSearchStoredState: Equatable {
    let cursor: ChatSearchCursor?
    let isExhausted: Bool
    let visibilityRevision: UInt64
    let count: Int
    // commitPage의 이번 transaction 삽입 수다. 상태 재조회/차단 갱신에서는 0이다.
    var insertedCount: Int = 0
}

protocol ChatSearchPersisting {
    func createSession(scope: ChatSearchScope, visibilityRevision: UInt64, blockedAuthorIDs: Set<String>) async throws
    func commitPage(identity: ChatSearchSessionIdentity, visibilityRevision: UInt64,
                    expectedCursor: ChatSearchCursor?, hits: [ChatSearchResultMetadata],
                    nextCursor: ChatSearchCursor?, isExhausted: Bool) async throws -> ChatSearchStoredState
    func applyVisibility(identity: ChatSearchSessionIdentity, revision: UInt64, blockedAuthorIDs: Set<String>) async throws -> ChatSearchStoredState
    func state(identity: ChatSearchSessionIdentity) async throws -> ChatSearchStoredState
    func results(identity: ChatSearchSessionIdentity, offset: Int, limit: Int) async throws -> [ChatSearchResultMetadata]
    func ordinal(identity: ChatSearchSessionIdentity, messageID: String) async throws -> Int?
    func neighbor(identity: ChatSearchSessionIdentity, anchor: ChatSearchResultMetadata, direction: ChatSearchDirection) async throws -> ChatSearchResultMetadata?
    func closeSession(identity: ChatSearchSessionIdentity) async throws
}
