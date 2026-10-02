import Foundation
import FirebaseFunctions
import FirebaseFirestore

final class ChatSearchValidationRepository: ChatSearchValidating {
    let access: ChatModerationLifecycleRepositoryProtocol
    let deletion: ChatDeletionSyncUseCaseProtocol?
    let currentAccountID: @Sendable () -> String
    init(access: ChatModerationLifecycleRepositoryProtocol, deletion: ChatDeletionSyncUseCaseProtocol?,
         currentAccountID: @escaping @Sendable () -> String) {
        self.access = access; self.deletion = deletion; self.currentAccountID = currentAccountID
    }
    func validateAccess(accountID: String, roomID: String) async throws {
        guard currentAccountID() == accountID else { throw ChatSearchFailure.accessLost }
        do {
            let result = try await access.fetchMyRoomAccess(roomID: roomID)
            guard result == .member else { throw result == .closed ? ChatSearchFailure.roomClosed : .accessLost }
        } catch { throw Self.classify(error) }
    }
    func reconcileDeletion(accountID: String, roomID: String) async throws {
        guard currentAccountID() == accountID else { throw ChatSearchFailure.accessLost }
        guard let deletion else { throw ChatSearchFailure.indexConfiguration }
        do { _ = try await deletion.reconcile(roomID: roomID, accountID: accountID, allowEmptyLocalBootstrap: false) }
        catch { throw Self.classify(error) }
    }
    static func classify(_ error: Error) -> Error {
        if error is ChatSearchFailure || error is CancellationError { return error }
        let ns = error as NSError
        guard ns.domain == FunctionsErrorDomain || ns.domain == FirestoreErrorDomain else { return ChatSearchFailure.malformedData }
        switch ns.code {
        case 1: return CancellationError()
        case 4, 8, 14: return ChatSearchFailure.transientNetwork
        case 7, 16: return ChatSearchFailure.accessLost
        case 9: return ChatSearchFailure.indexConfiguration
        default: return ChatSearchFailure.malformedData
        }
    }
}
