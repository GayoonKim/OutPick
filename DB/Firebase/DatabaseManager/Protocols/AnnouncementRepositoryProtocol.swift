//
//  AnnouncementRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation

/// 공지 관련 데이터베이스 작업을 위한 프로토콜
protocol AnnouncementRepositoryProtocol {
    /// 활성 공지 설정 (roomID 기반)
    func setActiveAnnouncement(roomID: String, messageID: String?, payload: AnnouncementPayload?) async throws
    
    /// 활성 공지 설정 (room 객체 기반)
    func setActiveAnnouncement(room: ChatRoom, messageID: String?, payload: AnnouncementPayload?) async throws
    
    /// 활성 공지 설정 (간편 버전 - 텍스트/작성자만)
    func setActiveAnnouncement(room: ChatRoom, text: String, authorID: String) async throws
    
    /// 활성 공지 제거 (roomID 기반)
    func clearActiveAnnouncement(roomID: String) async throws
    
    /// 활성 공지 제거 (room 객체 기반)
    func clearActiveAnnouncement(room: ChatRoom) async throws
}


