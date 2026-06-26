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
        avatarImageManager: AvatarImageManaging,
        currentUserProvider: CurrentUserProviding,
        repositories: FirebaseRepositoryProviding,
        photoLibrarySaver: PhotoLibrarySaving = DefaultPhotoLibrarySaver(),
        onBack: @escaping () -> Void
    ) -> UserProfileDetailViewController {
        let repository = UserProfileDetailRepository(
            userProfileRepository: repositories.userProfileRepository
        )
        let useCase = LoadUserProfileDetailUseCase(repository: repository)
        let viewModel = UserProfileDetailViewModel(
            lookupKey: .email(email),
            seedNickname: seedNickname,
            seedAvatarSource: AvatarImageSource(seedPath: seedAvatarPath),
            currentUserID: currentUserProvider.documentID,
            currentUserEmail: currentUserProvider.email,
            loadUserProfileDetailUseCase: useCase,
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

    static func makeDetail(
        userID: String,
        seedNickname: String,
        seedAvatarPath: String?,
        avatarImageManager: AvatarImageManaging,
        currentUserProvider: CurrentUserProviding,
        repositories: FirebaseRepositoryProviding,
        photoLibrarySaver: PhotoLibrarySaving = DefaultPhotoLibrarySaver(),
        onBack: @escaping () -> Void
    ) -> UserProfileDetailViewController {
        let repository = UserProfileDetailRepository(
            userProfileRepository: repositories.userProfileRepository
        )
        let useCase = LoadUserProfileDetailUseCase(repository: repository)
        let viewModel = UserProfileDetailViewModel(
            lookupKey: .userID(userID),
            seedNickname: seedNickname,
            seedAvatarSource: AvatarImageSource(seedPath: seedAvatarPath),
            currentUserID: currentUserProvider.documentID,
            currentUserEmail: currentUserProvider.email,
            loadUserProfileDetailUseCase: useCase,
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
