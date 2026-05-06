//
//  FilterBlockedCommentAuthorsUseCase.swift
//  OutPick
//
//  Created by Codex on 5/6/26.
//

import Foundation

struct FilterBlockedCommentAuthorsUseCase {
    func execute(
        comments: [Comment],
        blockedUserIDs: Set<UserID>
    ) -> [Comment] {
        guard blockedUserIDs.isEmpty == false else { return comments }
        return comments.filter { blockedUserIDs.contains($0.userID) == false }
    }
}
