//
//  Metrics.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

// MARK: - 집계 지표 (트렌딩/정렬에 사용)
struct PostMetrics: Equatable, Codable {
    let likeCount: Int
    let commentCount: Int
    let replacementCount: Int
    let saveCount: Int
    let viewCount: Int?
}

struct BrandMetrics: Equatable, Codable {
    var likeCount: Int
    var viewCount: Int
    var popularScore: Double
}
