import Foundation

enum ChatRoomMemberRemovalReason: String, CaseIterable {
    case harassment
    case hate
    case sexual
    case spam
    case privacy
    case illegalDangerous
    case other

    var title: String {
        switch self {
        case .harassment: "괴롭힘 또는 따돌림"
        case .hate: "혐오 표현"
        case .sexual: "성적인 콘텐츠"
        case .spam: "스팸"
        case .privacy: "개인정보 침해"
        case .illegalDangerous: "불법·위험 행위"
        case .other: "기타"
        }
    }
}

protocol ChatRoomMemberModerationUseCaseProtocol {
    func loadMyRoomAccess(roomID: String) async throws -> ChatRoomAccessStatus
    func removeMember(roomID: String, targetUID: String, reasonCode: String) async throws -> ChatRoomMemberRemovalReceipt
    func loadBans(roomID: String, cursor: String?) async throws -> ChatRoomBanPage
    func unban(roomID: String, token: String) async throws
}

final class ChatRoomMemberModerationUseCase: ChatRoomMemberModerationUseCaseProtocol {
    private let repository: ChatModerationLifecycleRepositoryProtocol

    init(repository: ChatModerationLifecycleRepositoryProtocol) {
        self.repository = repository
    }

    func loadMyRoomAccess(roomID: String) async throws -> ChatRoomAccessStatus {
        try await repository.fetchMyRoomAccess(roomID: roomID)
    }

    func removeMember(
        roomID: String,
        targetUID: String,
        reasonCode: String
    ) async throws -> ChatRoomMemberRemovalReceipt {
        try await repository.removeRoomMember(
            roomID: roomID,
            targetUID: targetUID,
            reasonCode: reasonCode
        )
    }

    func loadBans(roomID: String, cursor: String? = nil) async throws -> ChatRoomBanPage {
        try await repository.listRoomBans(roomID: roomID, pageSize: 50, cursor: cursor)
    }

    func unban(roomID: String, token: String) async throws {
        try await repository.unbanRoomMember(roomID: roomID, banEntryToken: token)
    }
}
