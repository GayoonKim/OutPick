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
    let onBack: () -> Void

    func makeUIViewController(context: Context) -> UserProfileDetailViewController {
        UserProfileDetailCompositionRoot.makeDetail(
            userID: author.userID.value,
            seedNickname: author.nickname,
            seedAvatarPath: author.avatarPath,
            provider: ChatDependencyContainer.provider,
            repositories: FirebaseRepositoryProvider.shared,
            onBack: onBack
        )
    }

    func updateUIViewController(_ uiViewController: UserProfileDetailViewController, context: Context) {}
}
