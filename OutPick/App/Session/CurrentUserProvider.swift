//
//  CurrentUserProvider.swift
//  OutPick
//
//  Created by Codex on 6/18/26.
//

import Foundation

protocol CurrentUserProviding {
    var email: String { get }
    var canonicalUserID: String { get }
    var nickname: String? { get }
    var avatarPath: String? { get }
    var profile: UserProfile? { get }
}

struct LoginManagerCurrentUserProvider: CurrentUserProviding {
    private let loginManager: LoginManager
    private let sessionStore: CurrentUserSessionStore

    init(
        loginManager: LoginManager = .shared,
        sessionStore: CurrentUserSessionStore = CurrentUserSessionStore()
    ) {
        self.loginManager = loginManager
        self.sessionStore = sessionStore
    }

    var email: String {
        loginManager.getUserEmail
    }

    var canonicalUserID: String {
        loginManager.canonicalUserID
    }

    var nickname: String? {
        sessionStore.currentProfile?.nickname
    }

    var avatarPath: String? {
        sessionStore.currentProfile?.thumbPath
    }

    var profile: UserProfile? {
        sessionStore.currentProfile
    }
}
