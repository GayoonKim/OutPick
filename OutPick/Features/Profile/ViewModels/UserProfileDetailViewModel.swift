//
//  UserProfileDetailViewModel.swift
//  OutPick
//

import Foundation

@MainActor
final class UserProfileDetailViewModel {
    struct State: Equatable {
        var nickname: String
        var avatarSource: AvatarImageSource
        var isLoading: Bool = false
        var isCurrentUser: Bool = false
    }

    private(set) var state: State {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?

    private let userID: String
    private let currentUserID: String?
    private let loadUserProfileDetailUseCase: LoadUserProfileDetailUseCaseProtocol
    private let onBack: () -> Void
    private var hasLoaded = false

    init(
        userID: String,
        seedNickname: String,
        seedAvatarSource: AvatarImageSource,
        currentUserID: String?,
        loadUserProfileDetailUseCase: LoadUserProfileDetailUseCaseProtocol,
        onBack: @escaping () -> Void
    ) {
        self.userID = userID
        self.currentUserID = currentUserID?.normalizedForComparison
        self.loadUserProfileDetailUseCase = loadUserProfileDetailUseCase
        self.onBack = onBack

        let fallbackNickname = seedNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        self.state = State(
            nickname: fallbackNickname.isEmpty ? "알 수 없는 사용자" : fallbackNickname,
            avatarSource: seedAvatarSource,
            isCurrentUser: Self.isCurrentUser(
                userID: userID,
                currentUserID: self.currentUserID
            )
        )
    }

    func viewDidLoad() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { await loadProfile() }
    }

    func backTapped() {
        onBack()
    }

    private func loadProfile() async {
        state.isLoading = true

        defer {
            state.isLoading = false
        }

        do {
            let profile = try await loadUserProfileDetailUseCase.execute(userID: userID)
            if let nickname = profile.nickname?.trimmingCharacters(in: .whitespacesAndNewlines),
               !nickname.isEmpty {
                state.nickname = nickname
            }

            state.avatarSource = state.avatarSource.merged(with: profile)
            state.isCurrentUser = Self.isCurrentUser(
                userID: userID,
                currentUserID: currentUserID
            )
        } catch {
            // seed data를 그대로 유지해 즉시 표시한다.
        }
    }

    private static func isCurrentUser(
        userID: String,
        currentUserID: String?
    ) -> Bool {
        userID.normalizedForComparison == currentUserID
    }
}

private extension String {
    var normalizedForComparison: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
