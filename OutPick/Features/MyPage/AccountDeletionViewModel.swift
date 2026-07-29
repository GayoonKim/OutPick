import Foundation
import UIKit

@MainActor
final class AccountDeletionViewModel {
    struct State: Equatable {
        var isSubmitting = false
        var errorMessage: String?
    }

    private(set) var state = State() {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?
    var onAccepted: ((AccountDeletionRequestOutcome, AuthenticatedUser) -> Void)?

    private let expectedUser: AuthenticatedUser
    private let requestUseCase: RequestAccountDeletionUseCase

    init(
        expectedUser: AuthenticatedUser,
        requestUseCase: RequestAccountDeletionUseCase
    ) {
        self.expectedUser = expectedUser
        self.requestUseCase = requestUseCase
    }

    func requestDeletion(presenter: UIViewController) {
        guard state.isSubmitting == false else { return }
        state.isSubmitting = true
        state.errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let outcome = try await requestUseCase.execute(
                    expectedUser: expectedUser,
                    presenter: presenter
                )
                state.isSubmitting = false
                onAccepted?(outcome, expectedUser)
            } catch {
                state.isSubmitting = false
                state.errorMessage = Self.message(for: error)
            }
        }
    }

    private static func message(for error: Error) -> String {
        if error is CancellationError {
            return "계정 삭제 인증이 취소됐어요"
        }
        if let clientError = error as? AccountDeletionClientError {
            switch clientError {
            case .identityMismatch, .providerMismatch:
                return "현재 계정과 같은 계정으로 다시 인증해 주세요"
            case .missingAuthenticatedUser:
                return "로그인 정보를 확인할 수 없어요 다시 로그인해 주세요"
            case .invalidResponse, .receiptPersistenceFailed:
                return "삭제 요청 결과를 확인하지 못했어요 잠시 후 다시 시도해 주세요"
            }
        }
        return "계정 삭제를 요청하지 못했어요 잠시 후 다시 시도해 주세요"
    }
}

@MainActor
final class AccountDeletionPendingViewModel {
    struct State: Equatable {
        var status: AccountDeletionStatus = .grace
        var message = "계정 접근은 종료됐으며 삭제를 처리하고 있어요"
        var cancelableUntil: Date?
        var completedAt: Date?
        var isLoading = false
        var isCancelling = false
        var errorMessage: String?

        var canCancel: Bool {
            guard status.isCancelable else { return false }
            guard let cancelableUntil else { return true }
            return Date() < cancelableUntil
        }
    }

    private(set) var state: State {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?
    var onCancelled: ((AccountDeletionCancelOutcome) -> Void)?
    var onFinished: (() -> Void)?

    private let receipt: AccountDeletionReceipt?
    private let expectedUser: AuthenticatedUser?
    private let provider: AuthProvider
    private let loadStatusUseCase: LoadAccountDeletionStatusUseCase
    private let cancelUseCase: CancelAccountDeletionUseCase

    init(
        receipt: AccountDeletionReceipt?,
        expectedUser: AuthenticatedUser?,
        provider: AuthProvider,
        loadStatusUseCase: LoadAccountDeletionStatusUseCase,
        cancelUseCase: CancelAccountDeletionUseCase
    ) {
        self.receipt = receipt
        self.expectedUser = expectedUser
        self.provider = provider
        self.loadStatusUseCase = loadStatusUseCase
        self.cancelUseCase = cancelUseCase
        state = State(cancelableUntil: receipt?.cancelableUntil)
    }

    func load() {
        guard let receipt, state.isLoading == false else { return }
        state.isLoading = true
        state.errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await loadStatusUseCase.execute(receipt: receipt)
                state.status = snapshot.status
                state.message = snapshot.message
                state.cancelableUntil = snapshot.cancelableUntil ?? receipt.cancelableUntil
                state.completedAt = snapshot.completedAt
                state.isLoading = false
                if snapshot.status == .completed || snapshot.status == .cancelled {
                    try? loadStatusUseCase.removeReceipt()
                }
            } catch {
                state.isLoading = false
                state.errorMessage = "삭제 처리 상태를 불러오지 못했어요"
            }
        }
    }

    func cancelDeletion(presenter: UIViewController) {
        guard state.canCancel, state.isCancelling == false else { return }
        state.isCancelling = true
        state.errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let outcome = try await cancelUseCase.execute(
                    provider: provider,
                    expectedUser: expectedUser,
                    presenter: presenter
                )
                state.isCancelling = false
                onCancelled?(outcome)
            } catch {
                state.isCancelling = false
                state.errorMessage = "삭제 요청을 취소하지 못했어요 인증 계정과 취소 기간을 확인해 주세요"
            }
        }
    }

    func finishedTapped() {
        onFinished?()
    }
}
