import Foundation

protocol ChatModerationReportingRepositoryProtocol {
    func submitMessageReport(
        _ command: ChatMessageReportCommand
    ) async throws -> ChatMessageReportReceipt

    func submitUserReport(
        _ command: ChatUserReportCommand
    ) async throws -> ChatModerationReportReceipt

    func submitRoomReport(
        _ command: ChatRoomReportCommand
    ) async throws -> ChatModerationReportReceipt
}

final class CloudFunctionsChatModerationReportingRepository:
    ChatModerationReportingRepositoryProtocol {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) {
        self.transport = transport
    }

    func submitMessageReport(
        _ command: ChatMessageReportCommand
    ) async throws -> ChatMessageReportReceipt {
        var data: [String: Any] = [
            "roomID": command.roomID,
            "messageID": command.messageID,
            "reason": command.reason.rawValue,
            "clientRequestID": command.clientRequestID.uuidString.lowercased()
        ]
        if let detail = command.detail { data["detail"] = detail }
        let response = try await transport.call("submitMessageReport", data: data)
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        guard let status = ChatMessageReportStatus(rawValue: try decoder.string("status")) else {
            throw CloudFunctionsClientError.invalidResponse
        }
        return ChatMessageReportReceipt(
            status: status,
            submissionID: decoder.optionalString("submissionID"),
            isDeduplicated: try decoder.bool("deduplicated"),
            isAlreadyReported: try decoder.bool("alreadyReported"),
            visibilityState: try decoder.string("visibilityState"),
            seq: decoder.optionalInt("seq").map(Int64.init),
            receivedAt: decoder.optionalDate("receivedAt"),
            originalReceivedAt: decoder.optionalDate("originalReceivedAt")
        )
    }

    func submitUserReport(
        _ command: ChatUserReportCommand
    ) async throws -> ChatModerationReportReceipt {
        var data: [String: Any] = [
            "targetUID": command.targetUserID,
            "reason": command.reason.rawValue,
            "clientRequestID": command.clientRequestID.uuidString.lowercased()
        ]
        if let detail = command.detail { data["detail"] = detail }
        if let roomID = command.roomID { data["roomID"] = roomID }
        if let messageID = command.triggerMessageID {
            data["triggerMessageID"] = messageID
        }
        let response = try await transport.call("submitUserReport", data: data)
        return try Self.receipt(from: response)
    }

    func submitRoomReport(
        _ command: ChatRoomReportCommand
    ) async throws -> ChatModerationReportReceipt {
        var data: [String: Any] = [
            "roomID": command.roomID,
            "reason": command.reason.rawValue,
            "clientRequestID": command.clientRequestID.uuidString.lowercased()
        ]
        if let detail = command.detail { data["detail"] = detail }
        if let messageID = command.triggerMessageID {
            data["triggerMessageID"] = messageID
        }
        let response = try await transport.call("submitRoomReport", data: data)
        return try Self.receipt(from: response)
    }

    private static func receipt(
        from response: [String: Any]
    ) throws -> ChatModerationReportReceipt {
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        guard let receivedAt = decoder.optionalDate("receivedAt") else {
            throw CloudFunctionsClientError.invalidResponse
        }
        return ChatModerationReportReceipt(
            submissionID: try decoder.string("submissionID"),
            isDeduplicated: try decoder.bool("deduplicated"),
            receivedAt: receivedAt
        )
    }
}
