//
//  CommentUserProfileDetailView.swift
//  OutPick
//
//  Created by Codex on 5/5/26.
//

import SwiftUI
import UIKit

struct CommentUserProfileDetailView: UIViewControllerRepresentable {
    let author: CommentAuthorDisplay
    let avatarImageManager: AvatarImageManaging
    let currentUserProvider: any CurrentUserProviding
    let repositories: any FirebaseRepositoryProviding
    let onBack: () -> Void

    func makeUIViewController(context: Context) -> UserProfileDetailViewController {
        UserProfileDetailCompositionRoot.makeDetail(
            userID: author.userID.value,
            seedNickname: author.nickname,
            seedAvatarPath: author.avatarPath,
            avatarImageManager: avatarImageManager,
            currentUserProvider: currentUserProvider,
            repositories: repositories,
            onBack: onBack
        )
    }

    func updateUIViewController(_ uiViewController: UserProfileDetailViewController, context: Context) {}
}
