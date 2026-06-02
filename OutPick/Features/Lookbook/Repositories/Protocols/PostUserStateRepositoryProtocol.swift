//
//  PostUserStateRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

struct PostUserStatePage {
    let items: [PostUserState]
    let last: DocumentSnapshot?
}

protocol PostUserStateRepositoryProtocol {
    func fetchPostUserState(
        userID: UserID,
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID
    ) async throws -> PostUserState?

    func fetchLikedPostUserStates(
        userID: UserID,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> PostUserStatePage
}
