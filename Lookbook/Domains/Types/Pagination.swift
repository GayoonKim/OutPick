//
//  Pagination.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

// 커서 기반 페이지네이션을 Domain에서 추상화 (Firestore DocumentSnapshot 직접 노출 X)
struct PageCursor: Equatable, Codable {
    let token: String
}
struct PageRequest: Equatable, Codable {
    let size: Int
    let cursor: PageCursor?
}
struct PageResponse<T: Equatable>: Equatable {
    let items: [T]
    let nextCursor: PageCursor?
}
