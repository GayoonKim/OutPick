import UIKit

@MainActor
final class MyPageCoordinator {
    private let navigationController: UINavigationController
    private let container: MyPageContainer
    private var rootViewModel: MyPageViewModel?

    init(
        navigationController: UINavigationController,
        container: MyPageContainer
    ) {
        self.navigationController = navigationController
        self.container = container
    }

    func start() {
        Task { [updateUseCase = container.updatePublicProfileUseCase] in
            await updateUseCase.retryPendingCleanup()
        }
        let viewModel = MyPageViewModel(
            userID: container.userID,
            accountRepository: container.accountRepository,
            publicProfileRepository: container.publicProfileRepository,
            moodRepository: container.moodRepository,
            stylePreferenceStore: container.stylePreferenceStore,
            initialProfile: container.currentUserProvider.profile
        )
        viewModel.onEditProfile = { [weak self] profile in
            self?.showProfileEdit(profile: profile)
        }
        viewModel.onEditStyles = { [weak self] selectedMoodIDs in
            self?.showStyleEdit(selectedMoodIDs: selectedMoodIDs)
        }
        viewModel.onOpenBrandRequests = { [weak self] in
            self?.showBrandRequests()
        }
        viewModel.onOpenBlockedUsers = { [weak self] in
            self?.showBlockedUsers()
        }
        viewModel.onDeleteAccount = { [weak self] in
            self?.showAccountDeletion()
        }
        rootViewModel = viewModel
        navigationController.setViewControllers([
            MyPageViewController(
                viewModel: viewModel,
                avatarImageManager: container.avatarImageManager
            )
        ], animated: false)
        navigationController.setNavigationBarHidden(true, animated: false)
    }

    private func showProfileEdit(profile: UserPublicProfile) {
        let viewModel = ProfileEditViewModel(
            currentProfile: profile,
            updateUseCase: container.updatePublicProfileUseCase,
            onSaved: { [weak self] outcome in
                guard let self else { return }
                self.container.sessionStore.replaceProfile(outcome.profile)
                self.rootViewModel?.apply(profile: outcome.profile)
                self.navigationController.popViewController(animated: true)
                if outcome.oldAvatarCleanupFailed {
                    self.presentCleanupWarning()
                }
            }
        )
        let viewController = ProfileEditViewController(
            viewModel: viewModel,
            avatarImageManager: container.avatarImageManager
        )
        viewController.hidesBottomBarWhenPushed = true
        navigationController.pushViewController(viewController, animated: true)
    }

    private func showStyleEdit(selectedMoodIDs: [String]) {
        let viewModel = StylePreferenceEditViewModel(
            initialMoodIDs: selectedMoodIDs,
            moodRepository: container.moodRepository,
            updateUseCase: container.updateStylePreferencesUseCase,
            onSaved: { [weak self] selectedIDs, moods in
                guard let self else { return }
                self.container.stylePreferenceStore.replace(selectedMoodIDs: selectedIDs)
                self.rootViewModel?.apply(selectedMoodIDs: selectedIDs, moods: moods)
                self.navigationController.popViewController(animated: true)
            }
        )
        let viewController = StylePreferenceEditViewController(viewModel: viewModel)
        viewController.hidesBottomBarWhenPushed = true
        navigationController.pushViewController(viewController, animated: true)
    }

    private func showBrandRequests() {
        guard let appContentRouter = container.appContentRouter else {
            presentBrandRequestsRouteError()
            return
        }

        Task { [weak self] in
            do {
                try await appContentRouter.openMyBrandRequests()
            } catch {
                self?.presentBrandRequestsRouteError()
            }
        }
    }

    private func showBlockedUsers() {
        let viewModel = BlockedUsersViewModel(
            currentUserID: container.userID,
            repository: container.userBlockRepository,
            unblockUserUseCase: container.unblockUserUseCase
        )
        let viewController = BlockedUsersViewController(viewModel: viewModel)
        viewController.hidesBottomBarWhenPushed = true
        navigationController.pushViewController(viewController, animated: true)
    }

    private func showAccountDeletion() {
        guard let authenticatedUser = LoginManager.shared.authenticatedUser else {
            let alert = UIAlertController(
                title: "로그인 정보를 확인할 수 없어요",
                message: "다시 로그인한 뒤 계정 삭제를 요청해 주세요.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "확인", style: .default))
            navigationController.present(alert, animated: true)
            return
        }

        let viewModel = AccountDeletionViewModel(
            expectedUser: authenticatedUser,
            requestUseCase: container.requestAccountDeletionUseCase
        )
        viewModel.onAccepted = container.onAccountDeletionAccepted
        let viewController = AccountDeletionConfirmationViewController(viewModel: viewModel)
        viewController.hidesBottomBarWhenPushed = true
        navigationController.pushViewController(viewController, animated: true)
    }

    private func presentBrandRequestsRouteError() {
        let alert = UIAlertController(
            title: "요청 내역을 열 수 없어요",
            message: "잠시 후 다시 시도해 주세요.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        navigationController.present(alert, animated: true)
    }

    private func presentCleanupWarning() {
        let alert = UIAlertController(
            title: "프로필은 저장됐어요",
            message: "이전 이미지 정리를 완료하지 못했어요 잠시 후 다시 시도해 주세요",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        navigationController.present(alert, animated: true)
    }
}
