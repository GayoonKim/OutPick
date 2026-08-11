//
//  CommentUserProfileDetailView.swift
//  OutPick
//
//  Created by Codex on 5/5/26.
//

import SwiftUI
import UIKit
import FirebaseFirestore

struct CommentUserProfileDetailView: UIViewControllerRepresentable {
    let author: CommentAuthorDisplay
    let avatarImageManager: AvatarImageManaging
    let currentUserProvider: any CurrentUserProviding
    let repositories: any FirebaseRepositoryProviding
    let blockUserUseCase: any BlockUserUseCaseProtocol
    let userBlockVisibilityStore: any UserBlockVisibilityChecking
    let onBack: () -> Void

    func makeUIViewController(context: Context) -> UserProfileDetailViewController {
        UserProfileDetailCompositionRoot.makeDetail(
            userID: author.userID.value,
            seedNickname: author.nickname,
            seedAvatarPath: author.avatarPath,
            avatarImageManager: avatarImageManager,
            currentUserProvider: currentUserProvider,
            publicProfileRepository: FirestoreUserPublicProfileRepository(db: .firestore()),
            blockUserUseCase: blockUserUseCase,
            userBlockVisibilityStore: userBlockVisibilityStore,
            onBack: onBack
        )
    }

    func updateUIViewController(_ uiViewController: UserProfileDetailViewController, context: Context) {}
}
