import Testing
@testable import OutPick

struct GoogleAccountDeletionReauthenticationPolicyTests {
    @Test func missingFirebaseSessionSignsInForPendingCancellation() throws {
        let mode = try GoogleAccountDeletionReauthenticationPolicy.mode(
            currentFirebaseUserID: nil,
            expectedFirebaseUserID: "expected-user"
        )

        #expect(mode == .signIn)
    }

    @Test func matchingFirebaseSessionUsesReauthentication() throws {
        let mode = try GoogleAccountDeletionReauthenticationPolicy.mode(
            currentFirebaseUserID: "expected-user",
            expectedFirebaseUserID: "expected-user"
        )

        #expect(mode == .reauthenticate)
    }

    @Test func differentFirebaseSessionIsRejected() {
        #expect(throws: AccountDeletionClientError.identityMismatch) {
            try GoogleAccountDeletionReauthenticationPolicy.mode(
                currentFirebaseUserID: "different-user",
                expectedFirebaseUserID: "expected-user"
            )
        }
    }
}
