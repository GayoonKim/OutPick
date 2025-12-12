//
//  HotUserManagerProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import Combine

/// 실시간 프로필 업데이트를 위한 HotUser 관리 프로토콜
protocol HotUserManagerProtocol {
    /// HotUser 풀 업데이트
    func updateHotUserPool(for email: String, lastSeenAt: Date)
    
    /// HotUser 풀 시드 (초기 로드 시)
    func seedHotUserPool(with messages: [ChatMessage])
    
    /// 프로필 변경 구독
    func bindHotUser(email: String, onProfileChanged: @escaping (UserProfile) -> Void) -> AnyCancellable?
    
    /// 모든 HotUser 구독 해제
    func resetHotUserPool()
    
    /// 현재 HotUser 이메일 목록 반환
    func getHotUserEmails() -> [String]
}

