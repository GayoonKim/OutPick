//
//  UserProfileDetailCompositionRoot.swift
//  OutPick
//

import UIKit

@MainActor
enum UserProfileDetailCompositionRoot {
    static func makeDetail(
        userID: String,
        seedNickname: String,
        seedAvatarPath: String?,
        avatarImageManager: AvatarImageManaging,
        currentUserProvider: CurrentUserProviding,
        publicProfileRepository: UserPublicProfileRepositoryProtocol,
        photoLibrarySaver: PhotoLibrarySaving = DefaultPhotoLibrarySaver(),
        blockUserUseCase: (any BlockUserUseCaseProtocol)? = nil,
        userBlockVisibilityStore: (any UserBlockVisibilityChecking)? = nil,
        onBack: @escaping () -> Void
    ) -> UserProfileDetailViewController {
        let repository = UserProfileDetailRepository(
            publicProfileRepository: publicProfileRepository
        )
        let useCase = LoadUserProfileDetailUseCase(repository: repository)
        let viewModel = UserProfileDetailViewModel(
            userID: userID,
            seedNickname: seedNickname,
            seedAvatarSource: AvatarImageSource(seedPath: seedAvatarPath),
            currentUserID: currentUserProvider.canonicalUserID,
            loadUserProfileDetailUseCase: useCase,
            blockUserUseCase: blockUserUseCase,
            userBlockVisibilityStore: userBlockVisibilityStore,
            onBack: onBack
        )
        let viewController = UserProfileDetailViewController(
            viewModel: viewModel,
            avatarImageManager: avatarImageManager,
            photoLibrarySaver: photoLibrarySaver
        )
        viewController.view.backgroundColor = OutPickTheme.ColorToken.backgroundBase
        return viewController
    }
}
