//
//  CurrentUserProvider.swift
//  OutPick
//
//  Created by Codex on 6/18/26.
//

import Foundation

protocol CurrentUserProviding {
    var email: String { get }
    var documentID: String { get }
    var authIdentityKey: String { get }
    var nickname: String? { get }
    var avatarPath: String? { get }
    var profile: UserProfile? { get }
}

struct LoginManagerCurrentUserProvider: CurrentUserProviding {
    private let loginManager: LoginManager

    init(loginManager: LoginManager = .shared) {
        self.loginManager = loginManager
    }

    var email: String {
        loginManager.getUserEmail
    }

    var documentID: String {
        loginManager.getUserDocumentID
    }

    var authIdentityKey: String {
        loginManager.getAuthIdentityKey
    }

    var nickname: String? {
        loginManager.currentUserProfile?.nickname
    }

    var avatarPath: String? {
        loginManager.currentUserProfile?.thumbPath
    }

    var profile: UserProfile? {
        loginManager.currentUserProfile
    }
}
