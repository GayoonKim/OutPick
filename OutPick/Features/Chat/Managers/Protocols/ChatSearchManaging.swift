//
//  ChatSearchManaging.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation

enum ChatMessageSearchSource: Equatable {
    case serverIndex
    case localOffline
    case localFallbackAfterServerFailure
}

struct ChatMessageSearchHit: Equatable {
    let message: ChatMessage
    let snippet: String?

    init(message: ChatMessage, snippet: String? = nil) {
        self.message = message
        self.snippet = snippet
    }
}

struct ChatMessageSearchResult: Equatable {
    let keyword: String
    let totalCount: Int
    let hits: [ChatMessageSearchHit]   // seq ASC
    let source: ChatMessageSearchSource
    let isAuthoritative: Bool          // true when sourced from server index
}

struct ChatMessageServerSearchResponse: Equatable {
    let totalCount: Int
    let hits: [ChatMessageSearchHit]   // seq ASC
}

enum ChatMessageSearchRemoteError: Error {
    case serverSearchAPIUnavailable
}

/// 채팅 메시지 검색 관련 프로토콜
protocol ChatSearchManaging {
    /// 메시지 검색
    func searchMessages(roomID: String, keyword: String) async throws -> ChatMessageSearchResult
    
    /// 검색 결과 하이라이트 적용
    func applyHighlight(messageIDs: Set<String>) -> Set<String>
    
    /// 하이라이트 제거
    func clearHighlight() -> Set<String>
}
