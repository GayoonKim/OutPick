//
//  PostUserStateRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

protocol PostUserStateRepositoryProtocol {
    func fetchPostUserState(userID: UserID, postID: PostID) async throws -> PostUserState?
}
