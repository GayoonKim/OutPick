import Foundation
import FirebaseFirestore

struct ChatMessageDeletionReceipt: Equatable {
    let messageID: String
    let seq: Int64
    let isDeleted: Bool
    let isDeduplicated: Bool
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
            return "방장이 채팅방을 삭제했어요."
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
}

final class CloudFunctionsChatModerationLifecycleRepository:
    ChatModerationLifecycleRepositoryProtocol {
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
