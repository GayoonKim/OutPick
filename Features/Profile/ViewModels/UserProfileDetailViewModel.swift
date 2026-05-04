//
//  UserProfileDetailViewModel.swift
//  OutPick
//

import Foundation

@MainActor
final class UserProfileDetailViewModel {
    enum LookupKey: Equatable {
        case email(String)
        case userID(String)
    }

    struct State: Equatable {
        var nickname: String
        var avatarSource: AvatarImageSource
        var isLoading: Bool = false
    }

    private(set) var state: State {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?

    private let lookupKey: LookupKey
    private let loadUserProfileDetailUseCase: LoadUserProfileDetailUseCaseProtocol
    private let onBack: () -> Void
    private var hasLoaded = false

    init(
        lookupKey: LookupKey,
        seedNickname: String,
        seedAvatarSource: AvatarImageSource,
        loadUserProfileDetailUseCase: LoadUserProfileDetailUseCaseProtocol,
        onBack: @escaping () -> Void
    ) {
        self.lookupKey = lookupKey
        self.loadUserProfileDetailUseCase = loadUserProfileDetailUseCase
        self.onBack = onBack

        let fallbackNickname = seedNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        self.state = State(
            nickname: fallbackNickname.isEmpty ? "알 수 없는 사용자" : fallbackNickname,
            avatarSource: seedAvatarSource
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
            let profile: UserProfile
            switch lookupKey {
            case .email(let email):
                profile = try await loadUserProfileDetailUseCase.execute(email: email)
            case .userID(let userID):
                profile = try await loadUserProfileDetailUseCase.execute(userID: userID)
            }
            if let nickname = profile.nickname?.trimmingCharacters(in: .whitespacesAndNewlines),
               !nickname.isEmpty {
                state.nickname = nickname
            }

            state.avatarSource = state.avatarSource.merged(with: profile)
        } catch {
            // seed data를 그대로 유지해 즉시 표시한다.
        }
    }
}
