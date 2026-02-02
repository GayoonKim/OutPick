//
//  PaginationManagerProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import FirebaseFirestore

/// 페이지네이션 상태 관리를 위한 프로토콜
protocol PaginationManagerProtocol {
    /// 메시지 페이지네이션 마지막 스냅샷
    var lastFetchedMessageSnapshot: DocumentSnapshot? { get set }
    
    /// 방 페이지네이션 마지막 스냅샷
    var lastFetchedRoomSnapshot: DocumentSnapshot? { get set }
    
    /// 검색 페이지네이션 마지막 스냅샷
    var lastSearchSnapshot: DocumentSnapshot? { get set }
    
    /// 현재 검색 키워드
    var currentSearchKeyword: String { get set }
    
    /// 페이지네이션 상태 초기화
    func resetPagination()
}


