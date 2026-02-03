//
//  ReplacementItem.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

// 대체템(구조화데이터)
struct ReplacementItem: Equatable, Codable, Identifiable {
    var id: ReplacementID
    var postID: PostID
    var title: String
    var brandName: String?
//    var price: Int?
//    var currency: String?
//    var buyURL: URL?
    var imageURL: URL?
    var tagIDs: [TagID]
//    var createdBy: UserID?
    var createdAt: Date
}
