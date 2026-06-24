//
//  LookbookCurrentUserIDProviderTests.swift
//  OutPickTests
//
//  Created by Codex on 6/24/26.
//

import Foundation
import Testing
@testable import OutPick

struct LookbookCurrentUserIDProviderTests {
    @Test func currentUserIDUsesDocumentIDBeforeAuthIdentityKey() {
        let provider = LookbookCurrentUserIDProvider(
            currentUserProvider: CurrentUserProviderStub(
                documentID: " document-user ",
                authIdentityKey: "auth-user"
            )
        )

        #expect(provider.currentUserID == UserID(value: "document-user"))
    }

    @Test func currentUserIDFallsBackToAuthIdentityKeyWhenDocumentIDIsBlank() {
        let provider = LookbookCurrentUserIDProvider(
            currentUserProvider: CurrentUserProviderStub(
                documentID: " \n\t ",
                authIdentityKey: " auth-user "
            )
        )

        #expect(provider.currentUserID == UserID(value: "auth-user"))
    }

    @Test func currentUserIDReturnsNilWhenDocumentIDAndAuthIdentityKeyAreBlank() {
        let provider = LookbookCurrentUserIDProvider(
            currentUserProvider: EmailTrapCurrentUserProvider()
        )

        #expect(provider.currentUserID == nil)
    }
}

private struct CurrentUserProviderStub: CurrentUserProviding {
    var email: String = "me@example.com"
    var documentID: String = ""
    var authIdentityKey: String = ""
    var nickname: String? = nil
    var avatarPath: String? = nil
    var profile: UserProfile? = nil
}

private struct EmailTrapCurrentUserProvider: CurrentUserProviding {
    var email: String {
        Issue.record("Lookbook current user ID adapter must not use email fallback.")
        return "email-should-not-be-used@example.com"
    }

    var documentID: String { "" }
    var authIdentityKey: String { " " }
    var nickname: String? { nil }
    var avatarPath: String? { nil }
    var profile: UserProfile? { nil }
}
