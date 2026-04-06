//
//  UserProfileDetailCompositionRoot.swift
//  OutPick
//

import UIKit

@MainActor
enum UserProfileDetailCompositionRoot {
    static func makeDetail(
        email: String,
        seedNickname: String,
        seedAvatarPath: String?,
        provider: ChatManagerProviding,
        repositories: FirebaseRepositoryProviding,
        onBack: @escaping () -> Void
    ) -> UserProfileDetailViewController {
        let repository = UserProfileDetailRepository(
            userProfileRepository: repositories.userProfileRepository
        )
        let useCase = LoadUserProfileDetailUseCase(repository: repository)
        let viewModel = UserProfileDetailViewModel(
            email: email,
            seedNickname: seedNickname,
            seedAvatarPath: seedAvatarPath,
            loadUserProfileDetailUseCase: useCase,
            onBack: onBack
        )
        let viewController = UserProfileDetailViewController(
            viewModel: viewModel,
            avatarImageManager: provider.avatarImageManager
        )
        viewController.view.backgroundColor = .white
        return viewController
    }
}
