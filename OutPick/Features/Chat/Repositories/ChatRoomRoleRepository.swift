import Foundation
import FirebaseFirestore

enum ChatRoomRoleSnapshotSource: Equatable, Sendable {
    case cache
    case server
}

struct ChatRoomRoleSnapshot: Equatable, Sendable {
    let roomID: String
    let status: ChatRoomAccessStatus
    let role: ChatRoomMemberRole?
    let source: ChatRoomRoleSnapshotSource
}

protocol ChatRoomRoleObservationCancelling: AnyObject {
    func cancel()
}

protocol ChatRoomRoleRepositoryProtocol {
    @discardableResult
    func observeCurrentRole(
        roomID: String,
        userID: String,
        onUpdate: @escaping @Sendable (ChatRoomRoleSnapshot) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) -> ChatRoomRoleObservationCancelling

    func fetchMemberRole(roomID: String, userID: String) async throws -> ChatRoomMemberRole?
}

final class FirestoreChatRoomRoleRepository: ChatRoomRoleRepositoryProtocol {
    private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    @discardableResult
    func observeCurrentRole(
        roomID: String,
        userID: String,
        onUpdate: @escaping @Sendable (ChatRoomRoleSnapshot) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) -> ChatRoomRoleObservationCancelling {
        let normalizedRoomID = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRoomID.isEmpty,
              !normalizedRoomID.contains("/"),
              !normalizedUserID.isEmpty,
              !normalizedUserID.contains("/") else {
            return EmptyChatRoomRoleObservation()
        }

        let reference = firestore.collection("users").document(normalizedUserID)
            .collection("joinedRooms").document(normalizedRoomID)
        let registration = reference.addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
            if let error {
                onError(error)
                return
            }
            guard let snapshot else { return }
            let source: ChatRoomRoleSnapshotSource = snapshot.metadata.isFromCache ? .cache : .server
            guard snapshot.exists else {
                onUpdate(ChatRoomRoleSnapshot(
                    roomID: normalizedRoomID,
                    status: .joinable,
                    role: nil,
                    source: source
                ))
                return
            }
            let role: ChatRoomMemberRole?
            if let rawRole = snapshot.get("role") as? String {
                guard let decodedRole = ChatRoomMemberRole(rawValue: rawRole) else {
                    onError(ChatRoomRoleRepositoryError.invalidRoleProjection)
                    return
                }
                role = decodedRole
            } else {
                // 역할 마이그레이션 전에는 세션의 캐시 역할을 유지한다.
                role = nil
            }
            onUpdate(ChatRoomRoleSnapshot(
                roomID: normalizedRoomID,
                status: .member,
                role: role,
                source: source
            ))
        }
        return FirestoreChatRoomRoleObservation(registration: registration)
    }

    func fetchMemberRole(roomID: String, userID: String) async throws -> ChatRoomMemberRole? {
        let normalizedRoomID = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRoomID.isEmpty,
              !normalizedRoomID.contains("/"),
              !normalizedUserID.isEmpty,
              !normalizedUserID.contains("/") else {
            throw ChatRoomRoleRepositoryError.invalidMemberReference
        }
        let snapshot = try await firestore.collection("Rooms").document(normalizedRoomID)
            .collection("members").document(normalizedUserID)
            .getDocument(source: .server)
        guard snapshot.exists else { return nil }
        guard let rawRole = snapshot.get("role") as? String else {
            // 역할 마이그레이션 전 참여자는 일반 참여자로 취급한다.
            return .member
        }
        guard let role = ChatRoomMemberRole(rawValue: rawRole) else {
            throw ChatRoomRoleRepositoryError.invalidRoleProjection
        }
        return role
    }
}

enum ChatRoomRoleRepositoryError: LocalizedError {
    case invalidRoleProjection
    case invalidMemberReference

    var errorDescription: String? {
        switch self {
        case .invalidRoleProjection:
            return "채팅방 역할 정보를 확인할 수 없습니다."
        case .invalidMemberReference:
            return "채팅방 참여자 정보를 확인할 수 없습니다."
        }
    }
}

private final class FirestoreChatRoomRoleObservation: ChatRoomRoleObservationCancelling {
    private var registration: ListenerRegistration?

    init(registration: ListenerRegistration) {
        self.registration = registration
    }

    func cancel() {
        registration?.remove()
        registration = nil
    }

    deinit {
        cancel()
    }
}

private final class EmptyChatRoomRoleObservation: ChatRoomRoleObservationCancelling {
    func cancel() {}
}
