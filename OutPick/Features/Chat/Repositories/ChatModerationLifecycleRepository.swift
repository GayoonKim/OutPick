import Foundation
import FirebaseFirestore

struct ChatMessageDeletionReceipt: Equatable {
    let messageID: String
    let seq: Int64
    let isDeleted: Bool
    let isDeduplicated: Bool
}

struct ChatRoomMemberRemovalReceipt: Equatable {
    let memberCount: Int
}

enum ChatRoomAccessStatus: String, Equatable {
    case member
    case joinable
    case banned
    case closed
}

struct ChatRoomRoleAccess: Equatable {
    let status: ChatRoomAccessStatus
    let role: ChatRoomMemberRole?
}

struct ChatRoomRoleMutationReceipt: Equatable {
    let roomID: String
    let subjectUID: String?
    let role: ChatRoomMemberRole?
    let moderatorCount: Int
    let memberCount: Int?
    let eventID: String?
    let seq: Int64?
    let ownerUID: String?
    let exitMode: ChatRoomExitMode?
    let isDeduplicated: Bool
}

struct ChatRoomBanEntry: Equatable, Identifiable {
    let token: String
    let reasonCode: String
    let displayName: String?
    let bannedAt: Date?

    var id: String { token }
}

struct ChatRoomBanPage: Equatable {
    let items: [ChatRoomBanEntry]
    let nextCursor: String?
}

enum ChatRoomClosureType: String, Equatable {
    case closedByOwner
    case closedByModeration
}

struct ChatRoomClosureNotice: Equatable, Identifiable {
    let roomID: String
    let roomName: String?
    let closureType: ChatRoomClosureType
    let noticeCode: String
    let closedAt: Date

    var id: String { roomID }

    var title: String {
        guard let roomName else { return "채팅방 이용이 종료됐어요" }
        return "“\(roomName)” 채팅방이 종료됐어요"
    }

    var message: String {
        switch closureType {
        case .closedByOwner:
            if noticeCode == "ownerDeleted" {
                return "방장이 없어 방이 종료됐어요."
            }
            return "방장이 채팅방을 종료했어요."
        case .closedByModeration:
            return "운영 정책에 따라 이용이 종료됐어요."
        }
    }
}

protocol ChatModerationLifecycleRepositoryProtocol {
    func deleteMessage(
        roomID: String,
        messageID: String,
        expectedSeq: Int64,
        reasonCode: String
    ) async throws -> ChatMessageDeletionReceipt

    func closeOwnedRoom(
        roomID: String,
        expectedLifecycleVersion: Int
    ) async throws -> ChatRoomExitResult

    func fetchClosureNotices() async throws -> [ChatRoomClosureNotice]
    func acknowledgeClosureNotice(roomID: String) async throws
    func fetchMyRoomAccess(roomID: String) async throws -> ChatRoomAccessStatus
    func removeRoomMember(roomID: String, targetUID: String, reasonCode: String) async throws -> ChatRoomMemberRemovalReceipt
    func listRoomBans(roomID: String, pageSize: Int, cursor: String?) async throws -> ChatRoomBanPage
    func unbanRoomMember(roomID: String, banEntryToken: String) async throws
}

protocol ChatRoomRoleMutationRepositoryProtocol {
    func fetchMyRoomRoleAccess(roomID: String) async throws -> ChatRoomRoleAccess
    func assignModerator(roomID: String, targetUID: String) async throws -> ChatRoomRoleMutationReceipt
    func revokeModerator(roomID: String, targetUID: String) async throws -> ChatRoomRoleMutationReceipt
    func resignModerator(roomID: String) async throws -> ChatRoomRoleMutationReceipt
    func leaveChatRoom(roomID: String) async throws -> ChatRoomRoleMutationReceipt
    func transferOwnershipAndLeave(
        roomID: String,
        successorUID: String
    ) async throws -> ChatRoomRoleMutationReceipt
}

final class CloudFunctionsChatModerationLifecycleRepository:
    ChatModerationLifecycleRepositoryProtocol,
    ChatRoomRoleMutationRepositoryProtocol {
    private let transport: any CloudFunctionsTransporting
    private let firestore: Firestore
    private let currentUserID: () -> String

    init(
        transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport(),
        firestore: Firestore = Firestore.firestore(),
        currentUserID: @escaping () -> String = { LoginManager.shared.canonicalUserID }
    ) {
        self.transport = transport
        self.firestore = firestore
        self.currentUserID = currentUserID
    }

    func deleteMessage(
        roomID: String,
        messageID: String,
        expectedSeq: Int64,
        reasonCode: String
    ) async throws -> ChatMessageDeletionReceipt {
        let response = try await transport.call(
            "deleteChatMessage",
            data: [
                "roomID": roomID,
                "messageID": messageID,
                "expectedSeq": expectedSeq,
                "reasonCode": reasonCode,
                "clientRequestID": UUID().uuidString.lowercased()
            ]
        )
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        return ChatMessageDeletionReceipt(
            messageID: try decoder.string("messageID"),
            seq: Int64(try decoder.int("seq")),
            isDeleted: try decoder.bool("isDeleted"),
            isDeduplicated: try decoder.bool("deduplicated")
        )
    }

    func closeOwnedRoom(
        roomID: String,
        expectedLifecycleVersion: Int
    ) async throws -> ChatRoomExitResult {
        _ = try await transport.call(
            "closeOwnedChatRoom",
            data: [
                "roomID": roomID,
                "expectedLifecycleVersion": expectedLifecycleVersion,
                "clientRequestID": UUID().uuidString.lowercased()
            ]
        )
        return ChatRoomExitResult(roomID: roomID, mode: .closed)
    }

    func fetchClosureNotices() async throws -> [ChatRoomClosureNotice] {
        let uid = currentUserID().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else { return [] }
        let snapshot = try await firestore.collection("users").document(uid)
            .collection("roomClosureNotices")
            .order(by: "closedAt")
            .getDocuments()
        return snapshot.documents.compactMap(Self.notice)
    }

    func acknowledgeClosureNotice(roomID: String) async throws {
        let response = try await transport.call(
            "acknowledgeRoomClosure",
            data: [
                "roomID": roomID,
                "clientRequestID": UUID().uuidString.lowercased()
            ]
        )
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        guard try decoder.bool("acknowledged") else {
            throw CloudFunctionsClientError.invalidResponse
        }
    }

    func fetchMyRoomAccess(roomID: String) async throws -> ChatRoomAccessStatus {
        try await fetchMyRoomRoleAccess(roomID: roomID).status
    }

    func fetchMyRoomRoleAccess(roomID: String) async throws -> ChatRoomRoleAccess {
        let response = try await transport.call("getMyRoomAccess", data: ["roomID": roomID])
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        guard let status = ChatRoomAccessStatus(rawValue: try decoder.string("status")) else {
            throw CloudFunctionsClientError.invalidResponse
        }
        let role: ChatRoomMemberRole?
        if let rawRole = decoder.optionalString("role") {
            guard let decodedRole = ChatRoomMemberRole(rawValue: rawRole) else {
                throw CloudFunctionsClientError.invalidResponse
            }
            role = decodedRole
        } else {
            role = nil
        }
        if status == .member, role == nil {
            throw CloudFunctionsClientError.invalidResponse
        }
        return ChatRoomRoleAccess(status: status, role: role)
    }

    func removeRoomMember(
        roomID: String,
        targetUID: String,
        reasonCode: String
    ) async throws -> ChatRoomMemberRemovalReceipt {
        let response = try await transport.call("removeRoomMember", data: [
            "roomID": roomID,
            "targetUID": targetUID,
            "reasonCode": reasonCode,
            "clientRequestID": UUID().uuidString.lowercased()
        ])
        return ChatRoomMemberRemovalReceipt(
            memberCount: try CloudFunctionResponseDecoder(dictionary: response).int("memberCount")
        )
    }

    func listRoomBans(
        roomID: String,
        pageSize: Int = 50,
        cursor: String? = nil
    ) async throws -> ChatRoomBanPage {
        var request: [String: Any] = ["roomID": roomID, "pageSize": pageSize]
        if let cursor { request["cursor"] = cursor }
        let response = try await transport.call("listRoomBans", data: request)
        guard let rawItems = response["items"] as? [[String: Any]] else {
            throw CloudFunctionsClientError.invalidResponse
        }
        let formatter = ISO8601DateFormatter()
        let items = try rawItems.map { item in
            guard let token = item["banEntryToken"] as? String,
                  let reasonCode = item["reasonCode"] as? String else {
                throw CloudFunctionsClientError.invalidResponse
            }
            return ChatRoomBanEntry(
                token: token,
                reasonCode: reasonCode,
                displayName: item["displayNameSnapshot"] as? String,
                bannedAt: (item["bannedAt"] as? String).flatMap(formatter.date(from:))
            )
        }
        return ChatRoomBanPage(
            items: items,
            nextCursor: response["nextCursor"] as? String
        )
    }

    func unbanRoomMember(roomID: String, banEntryToken: String) async throws {
        let response = try await transport.call("unbanRoomMember", data: [
            "roomID": roomID,
            "banEntryToken": banEntryToken,
            "clientRequestID": UUID().uuidString.lowercased()
        ])
        guard try CloudFunctionResponseDecoder(dictionary: response).bool("roomBanned") == false else {
            throw CloudFunctionsClientError.invalidResponse
        }
    }

    func assignModerator(
        roomID: String,
        targetUID: String
    ) async throws -> ChatRoomRoleMutationReceipt {
        try await roleMutation(
            name: "assignRoomModerator",
            roomID: roomID,
            subjectKey: "targetUID",
            subjectUID: targetUID
        )
    }

    func revokeModerator(
        roomID: String,
        targetUID: String
    ) async throws -> ChatRoomRoleMutationReceipt {
        try await roleMutation(
            name: "revokeRoomModerator",
            roomID: roomID,
            subjectKey: "targetUID",
            subjectUID: targetUID
        )
    }

    func resignModerator(roomID: String) async throws -> ChatRoomRoleMutationReceipt {
        try await roleMutation(name: "resignRoomModerator", roomID: roomID)
    }

    func leaveChatRoom(roomID: String) async throws -> ChatRoomRoleMutationReceipt {
        try await roleMutation(name: "leaveChatRoom", roomID: roomID)
    }

    func transferOwnershipAndLeave(
        roomID: String,
        successorUID: String
    ) async throws -> ChatRoomRoleMutationReceipt {
        try await roleMutation(
            name: "transferRoomOwnershipAndLeave",
            roomID: roomID,
            subjectKey: "successorUID",
            subjectUID: successorUID
        )
    }

    private func roleMutation(
        name: String,
        roomID: String,
        subjectKey: String? = nil,
        subjectUID: String? = nil
    ) async throws -> ChatRoomRoleMutationReceipt {
        var request: [String: Any] = [
            "roomID": roomID,
            "clientRequestID": UUID().uuidString.lowercased()
        ]
        if let subjectKey, let subjectUID {
            request[subjectKey] = subjectUID
        }
        let response = try await transport.call(name, data: request)
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        let role: ChatRoomMemberRole?
        if let rawRole = decoder.optionalString("role") {
            guard let decodedRole = ChatRoomMemberRole(rawValue: rawRole) else {
                throw CloudFunctionsClientError.invalidResponse
            }
            role = decodedRole
        } else {
            role = nil
        }
        let exitMode = decoder.optionalString("mode").map(ChatRoomExitMode.init(serverValue:))
        return ChatRoomRoleMutationReceipt(
            roomID: try decoder.string("roomID"),
            subjectUID: decoder.optionalString("subjectUID"),
            role: role,
            moderatorCount: try decoder.int("moderatorCount"),
            memberCount: decoder.optionalInt("memberCount"),
            eventID: decoder.optionalString("eventID"),
            seq: decoder.optionalInt("seq").map(Int64.init),
            ownerUID: decoder.optionalString("ownerUID"),
            exitMode: exitMode,
            isDeduplicated: try decoder.bool("deduplicated")
        )
    }

    private static func notice(_ document: QueryDocumentSnapshot) -> ChatRoomClosureNotice? {
        let data = document.data()
        guard let rawType = data["closureType"] as? String,
              let closureType = ChatRoomClosureType(rawValue: rawType),
              let noticeCode = data["closureNoticeCode"] as? String,
              let closedAt = data["closedAt"] as? Timestamp else {
            return nil
        }
        let roomName = (data["roomName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatRoomClosureNotice(
            roomID: document.documentID,
            roomName: roomName?.isEmpty == false ? roomName : nil,
            closureType: closureType,
            noticeCode: noticeCode,
            closedAt: closedAt.dateValue()
        )
    }
}
