//
//  AuthenticatedUser.swift
//  OutPick
//
//  Created by Codex on 4/16/26.
//

import Foundation

enum AuthProvider: String, Codable, Equatable, Sendable {
    case google
    case kakao
}

struct AuthenticatedUser: Codable, Equatable, Sendable {
    let identityKey: String
    let provider: AuthProvider
    let providerUserID: String
    let email: String?

    init(
        identityKey: String,
        provider: AuthProvider,
        providerUserID: String,
        email: String?
    ) {
        self.identityKey = identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.provider = provider
        self.providerUserID = providerUserID.trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedEmail = email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.email = normalizedEmail?.isEmpty == false ? normalizedEmail : nil
    }
}
