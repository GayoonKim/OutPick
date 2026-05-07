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
        hiddenUserIDs: Set<UserID>
    ) -> [Comment] {
        guard hiddenUserIDs.isEmpty == false else { return comments }
        return comments.filter { hiddenUserIDs.contains($0.userID) == false }
    }
}
