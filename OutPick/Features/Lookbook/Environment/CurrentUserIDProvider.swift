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

struct LookbookCurrentUserIDProvider: CurrentUserIDProviding {
    private let currentUserProvider: any CurrentUserProviding

    init(currentUserProvider: any CurrentUserProviding = LoginManagerCurrentUserProvider()) {
        self.currentUserProvider = currentUserProvider
    }

    var currentUserID: UserID? {
        let userDocumentID = normalized(currentUserProvider.documentID)
        if let userDocumentID {
            return UserID(value: userDocumentID)
        }

        return normalized(currentUserProvider.authIdentityKey)
            .map { UserID(value: $0) }
    }

    private func normalized(_ value: String) -> String? {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedValue.isEmpty ? nil : normalizedValue
    }
}

typealias LoginManagerCurrentUserIDProvider = LookbookCurrentUserIDProvider
