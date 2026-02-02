//
//  ChatSearchManagerProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation

/// 채팅 메시지 검색 관련 프로토콜
protocol ChatSearchManagerProtocol {
    /// 메시지 검색
    func searchMessages(roomID: String, keyword: String) async throws -> [ChatMessage]
    
    /// 검색 결과 하이라이트 적용
    func applyHighlight(messageIDs: Set<String>) -> Set<String>
    
    /// 하이라이트 제거
    func clearHighlight() -> Set<String>
}

