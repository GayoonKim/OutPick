import Foundation

protocol UserBlockRelationReading: AnyObject {
    func fetchBlockedUserIDs(blockerUserID: UserID) async throws -> Set<UserID>
}

@MainActor
protocol UserBlockSessionSynchronizing: AnyObject {
    func applyServerMutation(userID: String, targetUserID: String, isBlocked: Bool)
}

@MainActor
final class UserBlockSessionController: UserBlockSessionSynchronizing {
    private let repository: any UserBlockRelationReading
    private let snapshotStore: any UserBlockSnapshotPersisting
    private let visibilityStore: UserBlockVisibilityStore

    private(set) var activeUserID: String?

    init(
        repository: any UserBlockRelationReading,
        snapshotStore: any UserBlockSnapshotPersisting,
        visibilityStore: UserBlockVisibilityStore
    ) {
        self.repository = repository
        self.snapshotStore = snapshotStore
        self.visibilityStore = visibilityStore
    }

    func bootstrap(userID: String) async throws {
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUserID.isEmpty else {
            throw UserBlockSessionError.invalidUserID
        }

        activeUserID = normalizedUserID
        let cached = snapshotStore.load(userID: normalizedUserID)
        visibilityStore.replace(with: cached ?? [])

        do {
            let remote = try await repository.fetchBlockedUserIDs(
                blockerUserID: UserID(value: normalizedUserID)
            )
            let remoteIDs = Set(remote.map(\.value))
            guard activeUserID == normalizedUserID else { return }
            visibilityStore.replace(with: remoteIDs)
            snapshotStore.save(remoteIDs, userID: normalizedUserID)
        } catch {
            guard activeUserID == normalizedUserID else { return }
            guard cached == nil else { return }
            visibilityStore.clear()
            activeUserID = nil
            throw error
        }
    }

    func applyServerMutation(userID: String, targetUserID: String, isBlocked: Bool) {
        guard activeUserID == userID else { return }
        if isBlocked {
            visibilityStore.insert(targetUserID)
        } else {
            visibilityStore.remove(targetUserID)
        }
        snapshotStore.save(visibilityStore.blockedUserIDs(), userID: userID)
    }

    func stop() {
        activeUserID = nil
        visibilityStore.clear()
    }
}

enum UserBlockSessionError: Error {
    case invalidUserID
}
