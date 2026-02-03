//
//  SortOptions.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

// MARK: - 정렬/페이지네이션/필터 (화면 공통으로 재사용)
enum PostSortOption: String, Codable {
    case newest
    case mostCommented
    case mostReplaced
    case mostSaved
    case trending
}

enum BrandSort {
    case latest, likes, views, popular

    var primaryField: String {
        switch self {
        case .latest:  return "updatedAt"
        case .likes:   return "likeCount"
        case .views:   return "viewCount"
        case .popular: return "popularScore"
        }
    }
}
