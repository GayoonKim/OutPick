//
//  CurrentUserIDProvider.swift
//  OutPick
//
//  Created by Codex on 5/7/26.
//

import Foundation

protocol CurrentUserIDProviding {
    var currentUserID: UserID? { get }
}

struct LoginManagerCurrentUserIDProvider: CurrentUserIDProviding {
    private let loginManager: LoginManager

    init(loginManager: LoginManager = .shared) {
        self.loginManager = loginManager
    }

    var currentUserID: UserID? {
        let userDocumentID = normalized(loginManager.getUserDocumentID)
        if let userDocumentID {
            return UserID(value: userDocumentID)
        }

        return normalized(loginManager.getAuthIdentityKey)
            .map { UserID(value: $0) }
    }

    private func normalized(_ value: String) -> String? {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedValue.isEmpty ? nil : normalizedValue
    }
}
