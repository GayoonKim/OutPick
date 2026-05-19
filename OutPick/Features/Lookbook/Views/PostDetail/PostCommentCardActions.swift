//
//  PostCommentCardActions.swift
//  OutPick
//
//  Created by Codex on 5/19/26.
//

struct PostCommentCardActions {
    var onProfileTap: (() -> Void)?
    var onLikeTap: (() async -> Void)?
    var onRepliesTap: (() -> Void)?
    var onCardTap: (() -> Void)?
    var onDeleteTap: (() -> Void)?
    var onReportTap: (() -> Void)?
    var onBlockTap: (() -> Void)?

    init(
        onProfileTap: (() -> Void)? = nil,
        onLikeTap: (() async -> Void)? = nil,
        onRepliesTap: (() -> Void)? = nil,
        onCardTap: (() -> Void)? = nil,
        onDeleteTap: (() -> Void)? = nil,
        onReportTap: (() -> Void)? = nil,
        onBlockTap: (() -> Void)? = nil
    ) {
        self.onProfileTap = onProfileTap
        self.onLikeTap = onLikeTap
        self.onRepliesTap = onRepliesTap
        self.onCardTap = onCardTap
        self.onDeleteTap = onDeleteTap
        self.onReportTap = onReportTap
        self.onBlockTap = onBlockTap
    }
}
