//
//  PostUserState.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

// 사용자별 상태(좋아요/저장)를 Post 모델에 섞지 않는" 편이 테스트/캐시가 편함
struct PostUserState: Equatable, Codable {
    var postID: PostID
    var userID: UserID
    var isLiked: Bool
    var isSaved: Bool
    var updatedAt: Date
}
