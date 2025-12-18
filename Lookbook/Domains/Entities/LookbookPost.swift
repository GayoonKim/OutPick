//
//  LookbookPost.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

struct LookbookPost: Equatable, Codable, Identifiable {
    
    var id: PostID
    var brandID: BrandID
    var seasonID: SeasonID
    var authorID: UserID?
    var media: [MediaAsset]     // 지금은 "사진 1장"이지만, 확장성 위해 배열 추천
    var caption: String?
    var tagIDs: [TagID]
    var metrics: PostMetrics
    var createdAt: Date
    var updatedAt: Date
}
