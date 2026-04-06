//
//  UserProfileDetailViewModel.swift
//  OutPick
//

import Foundation

@MainActor
final class UserProfileDetailViewModel {

    struct State: Equatable {
        var nickname: String
        var avatarPath: String?
        var isLoading: Bool = false
    }

    private(set) var state: State {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?

    private let email: String
    private let loadUserProfileDetailUseCase: LoadUserProfileDetailUseCaseProtocol
    private let onBack: () -> Void
    private var hasLoaded = false

    init(
        email: String,
        seedNickname: String,
        seedAvatarPath: String?,
        loadUserProfileDetailUseCase: LoadUserProfileDetailUseCaseProtocol,
        onBack: @escaping () -> Void
    ) {
        self.email = email
        self.loadUserProfileDetailUseCase = loadUserProfileDetailUseCase
        self.onBack = onBack

        let fallbackNickname = seedNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        self.state = State(
            nickname: fallbackNickname.isEmpty ? "알 수 없는 사용자" : fallbackNickname,
            avatarPath: seedAvatarPath
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
            let profile = try await loadUserProfileDetailUseCase.execute(email: email)
            if let nickname = profile.nickname?.trimmingCharacters(in: .whitespacesAndNewlines),
               !nickname.isEmpty {
                state.nickname = nickname
            }

            if let avatarPath = preferredAvatarPath(from: profile) {
                state.avatarPath = avatarPath
            }
        } catch {
            // seed data를 그대로 유지해 즉시 표시한다.
        }
    }

    private func preferredAvatarPath(from profile: UserProfile) -> String? {
        let thumbPath = profile.thumbPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let thumbPath, !thumbPath.isEmpty {
            return thumbPath
        }

        let originalPath = profile.originalPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let originalPath, !originalPath.isEmpty {
            return originalPath
        }

        return nil
    }
}
