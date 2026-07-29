import Foundation
import Testing
import UIKit
@testable import OutPick

@MainActor
struct AccountDeletionUseCaseTests {
    @Test
    func requestRunsReauthPrepareRequestReceiptAndScrubInOrder() async throws {
        let events = AccountDeletionEventRecorder()
        let repository = AccountDeletionRepositoryFake(events: events)
        let reauthenticator = AccountDeletionReauthenticatorSpy(events: events)
        let receiptStore = AccountDeletionReceiptStoreSpy(events: events)
        let scrubber = AccountDeletionLocalDataScrubberSpy(events: events)
        let useCase = RequestAccountDeletionUseCase(
            repository: repository,
            reauthenticator: reauthenticator,
            receiptStore: receiptStore,
            localDataScrubber: scrubber
        )

        let outcome = try await useCase.execute(
            expectedUser: Self.user,
            presenter: UIViewController()
        )

        #expect(events.values == ["reauth", "prepare", "request", "receipt.save", "scrub"])
        #expect(outcome.receiptPersisted)
        #expect(outcome.localCleanupCompleted)
        #expect(outcome.receipt.provider == .google)
    }

    @Test
    func failureBeforeServerAcceptanceKeepsReceiptAndLocalDataUntouched() async {
        let events = AccountDeletionEventRecorder()
        let repository = AccountDeletionRepositoryFake(
            events: events,
            requestError: AccountDeletionTestError.failed
        )
        let receiptStore = AccountDeletionReceiptStoreSpy(events: events)
        let scrubber = AccountDeletionLocalDataScrubberSpy(events: events)
        let useCase = RequestAccountDeletionUseCase(
            repository: repository,
            reauthenticator: AccountDeletionReauthenticatorSpy(events: events),
            receiptStore: receiptStore,
            localDataScrubber: scrubber
        )

        await #expect(throws: AccountDeletionTestError.failed) {
            try await useCase.execute(
                expectedUser: Self.user,
                presenter: UIViewController()
            )
        }
        #expect(events.values == ["reauth", "prepare", "request"])
        #expect(receiptStore.savedReceipt == nil)
        #expect(scrubber.scrubCount == 0)
    }

    @Test
    func acceptedRequestReturnsPendingOutcomeEvenWhenReceiptAndScrubFail() async throws {
        let events = AccountDeletionEventRecorder()
        let useCase = RequestAccountDeletionUseCase(
            repository: AccountDeletionRepositoryFake(events: events),
            reauthenticator: AccountDeletionReauthenticatorSpy(events: events),
            receiptStore: AccountDeletionReceiptStoreSpy(
                events: events,
                saveError: AccountDeletionTestError.failed
            ),
            localDataScrubber: AccountDeletionLocalDataScrubberSpy(
                events: events,
                scrubError: AccountDeletionTestError.failed
            )
        )

        let outcome = try await useCase.execute(
            expectedUser: Self.user,
            presenter: UIViewController()
        )

        #expect(outcome.receiptPersisted == false)
        #expect(outcome.localCleanupCompleted == false)
        #expect(events.values.suffix(2) == ["receipt.save", "scrub"])
    }

    @Test
    func cancellationRejectsDifferentProviderBeforeAuthenticationOrServerCall() async {
        let events = AccountDeletionEventRecorder()
        let repository = AccountDeletionRepositoryFake(events: events)
        let useCase = CancelAccountDeletionUseCase(
            repository: repository,
            reauthenticator: AccountDeletionReauthenticatorSpy(events: events),
            receiptStore: AccountDeletionReceiptStoreSpy(events: events)
        )

        await #expect(throws: AccountDeletionClientError.providerMismatch) {
            try await useCase.execute(
                provider: .kakao,
                expectedUser: Self.user,
                presenter: UIViewController()
            )
        }
        #expect(events.values.isEmpty)
    }

    @Test
    func pendingReceiptCancellationAuthenticatesThenCancelsAndRemovesReceipt() async throws {
        let events = AccountDeletionEventRecorder()
        let useCase = CancelAccountDeletionUseCase(
            repository: AccountDeletionRepositoryFake(events: events),
            reauthenticator: AccountDeletionReauthenticatorSpy(events: events),
            receiptStore: AccountDeletionReceiptStoreSpy(events: events)
        )

        let outcome = try await useCase.execute(
            provider: .google,
            expectedUser: nil,
            presenter: UIViewController()
        )

        #expect(events.values == ["authenticate.google", "cancel", "receipt.delete"])
        #expect(outcome.authenticatedUser == Self.user)
        #expect(outcome.receiptRemoved)
    }

    private static let user = AuthenticatedUser(
        identityKey: "user-1",
        provider: .google,
        providerUserID: "google-user-1",
        email: "user@outpick.local"
    )
}

@MainActor
private final class AccountDeletionEventRecorder {
    var values: [String] = []
}

private final class AccountDeletionRepositoryFake: AccountDeletionRepositoryProtocol {
    private let events: AccountDeletionEventRecorder
    private let requestError: Error?

    init(
        events: AccountDeletionEventRecorder,
        requestError: Error? = nil
    ) {
        self.events = events
        self.requestError = requestError
    }

    func prepareDeletion() async throws -> AccountDeletionIntent {
        await MainActor.run { events.values.append("prepare") }
        return AccountDeletionIntent(
            intentID: "intent-1",
            nonce: "nonce-1",
            expiresAt: Date(timeIntervalSince1970: 100)
        )
    }

    func requestDeletion(
        intent: AccountDeletionIntent
    ) async throws -> AccountDeletionReceiptPayload {
        await MainActor.run { events.values.append("request") }
        if let requestError { throw requestError }
        return AccountDeletionReceiptPayload(
            requestID: "request-1",
            receiptToken: "receipt-1",
            requestedAt: Date(timeIntervalSince1970: 200),
            cancelableUntil: Date(timeIntervalSince1970: 200 + 7 * 24 * 60 * 60)
        )
    }

    func cancelDeletion() async throws -> AccountDeletionCancellation {
        await MainActor.run { events.values.append("cancel") }
        return AccountDeletionCancellation(
            requestID: "request-1",
            cancelledAt: Date(timeIntervalSince1970: 300)
        )
    }

    func loadStatus(
        receipt: AccountDeletionReceipt
    ) async throws -> AccountDeletionStatusSnapshot {
        AccountDeletionStatusSnapshot(
            status: .grace,
            requestedAt: receipt.requestedAt,
            cancelableUntil: receipt.cancelableUntil,
            completedAt: nil,
            message: "취소할 수 있어요"
        )
    }
}

@MainActor
private final class AccountDeletionReauthenticatorSpy: AccountDeletionReauthenticating {
    private let events: AccountDeletionEventRecorder

    init(events: AccountDeletionEventRecorder) {
        self.events = events
    }

    func reauthenticateForAccountDeletion(
        expectedUser: AuthenticatedUser,
        presenter: UIViewController
    ) async throws {
        events.values.append("reauth")
    }

    func authenticatePendingAccount(
        provider: AuthProvider,
        presenter: UIViewController
    ) async throws -> AuthenticatedUser {
        events.values.append("authenticate.\(provider.rawValue)")
        return AuthenticatedUser(
            identityKey: "user-1",
            provider: .google,
            providerUserID: "google-user-1",
            email: "user@outpick.local"
        )
    }
}

private final class AccountDeletionReceiptStoreSpy: AccountDeletionReceiptStoring {
    private let events: AccountDeletionEventRecorder
    private let saveError: Error?
    private(set) var savedReceipt: AccountDeletionReceipt?

    init(
        events: AccountDeletionEventRecorder,
        saveError: Error? = nil
    ) {
        self.events = events
        self.saveError = saveError
    }

    func save(_ receipt: AccountDeletionReceipt) throws {
        MainActor.assumeIsolated { events.values.append("receipt.save") }
        if let saveError { throw saveError }
        savedReceipt = receipt
    }

    func load() throws -> AccountDeletionReceipt? {
        savedReceipt
    }

    func delete() throws {
        MainActor.assumeIsolated { events.values.append("receipt.delete") }
        savedReceipt = nil
    }
}

@MainActor
private final class AccountDeletionLocalDataScrubberSpy: AccountDeletionLocalDataScrubbing {
    private let events: AccountDeletionEventRecorder
    private let scrubError: Error?
    private(set) var scrubCount = 0

    init(
        events: AccountDeletionEventRecorder,
        scrubError: Error? = nil
    ) {
        self.events = events
        self.scrubError = scrubError
    }

    var requiresRetry: Bool { false }

    func scrub() async throws {
        scrubCount += 1
        events.values.append("scrub")
        if let scrubError { throw scrubError }
    }
}

private enum AccountDeletionTestError: Error, Equatable {
    case failed
}
