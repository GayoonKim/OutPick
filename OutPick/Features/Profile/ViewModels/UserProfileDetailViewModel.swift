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
        var isCurrentUser: Bool = false
    }

    private(set) var state: State {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?

    private let lookupKey: LookupKey
    private let currentUserID: String?
    private let currentUserEmail: String?
    private let loadUserProfileDetailUseCase: LoadUserProfileDetailUseCaseProtocol
    private let onBack: () -> Void
    private var hasLoaded = false

    init(
        lookupKey: LookupKey,
        seedNickname: String,
        seedAvatarSource: AvatarImageSource,
        currentUserID: String?,
        currentUserEmail: String?,
        loadUserProfileDetailUseCase: LoadUserProfileDetailUseCaseProtocol,
        onBack: @escaping () -> Void
    ) {
        self.lookupKey = lookupKey
        self.currentUserID = currentUserID?.normalizedForComparison
        self.currentUserEmail = currentUserEmail?.normalizedForComparison
        self.loadUserProfileDetailUseCase = loadUserProfileDetailUseCase
        self.onBack = onBack

        let fallbackNickname = seedNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        self.state = State(
            nickname: fallbackNickname.isEmpty ? "알 수 없는 사용자" : fallbackNickname,
            avatarSource: seedAvatarSource,
            isCurrentUser: Self.isCurrentUser(
                lookupKey: lookupKey,
                profile: nil,
                currentUserID: self.currentUserID,
                currentUserEmail: self.currentUserEmail
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
            state.isCurrentUser = Self.isCurrentUser(
                lookupKey: lookupKey,
                profile: profile,
                currentUserID: currentUserID,
                currentUserEmail: currentUserEmail
            )
        } catch {
            // seed data를 그대로 유지해 즉시 표시한다.
        }
    }

    private static func isCurrentUser(
        lookupKey: LookupKey,
        profile: UserProfile?,
        currentUserID: String?,
        currentUserEmail: String?
    ) -> Bool {
        switch lookupKey {
        case .userID(let userID):
            if userID.normalizedForComparison == currentUserID {
                return true
            }
        case .email(let email):
            if email.normalizedForComparison == currentUserEmail {
                return true
            }
        }

        guard let profile else { return false }
        return profile.email.normalizedForComparison == currentUserEmail
    }
}

private extension String {
    var normalizedForComparison: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
