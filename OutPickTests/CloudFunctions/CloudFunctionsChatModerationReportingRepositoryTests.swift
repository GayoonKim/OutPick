import Foundation
import Testing
@testable import OutPick

struct CloudFunctionsChatModerationReportingRepositoryTests {
    @Test
    func mapsUserAndRoomReportCallableContracts() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [
            [
                "submissionID": "submission-user",
                "deduplicated": false,
                "receivedAt": "2026-08-10T12:00:00.000Z"
            ],
            [
                "submissionID": "submission-room",
                "deduplicated": true,
                "receivedAt": "2026-08-10T12:01:00.000Z"
            ]
        ]
        let repository = CloudFunctionsChatModerationReportingRepository(
            transport: transport
        )
        let requestID = UUID(uuidString: "123E4567-E89B-42D3-A456-426614174000")!

        let userReceipt = try await repository.submitUserReport(
            ChatUserReportCommand(
                targetUserID: "user-2",
                reason: .harassment,
                detail: "반복적인 괴롭힘",
                roomID: "room-1",
                triggerMessageID: "message-1",
                clientRequestID: requestID
            )
        )
        let roomReceipt = try await repository.submitRoomReport(
            ChatRoomReportCommand(
                roomID: "room-1",
                reason: .spam,
                detail: nil,
                triggerMessageID: nil,
                clientRequestID: requestID
            )
        )

        #expect(transport.calls.map(\.name) == ["submitUserReport", "submitRoomReport"])
        #expect(transport.calls[0].data["targetUID"] as? String == "user-2")
        #expect(transport.calls[0].data["reason"] as? String == "harassment")
        #expect(
            transport.calls[0].data["clientRequestID"] as? String ==
                "123e4567-e89b-42d3-a456-426614174000"
        )
        #expect(userReceipt.submissionID == "submission-user")
        #expect(roomReceipt.isDeduplicated)
    }

    @Test
    func useCaseRejectsTriggerMessageWithoutRoomBeforeCallingRepository() async {
        let repository = ChatModerationReportingRepositoryFake()
        let useCase = SubmitChatModerationReportUseCase(repository: repository)

        await #expect(throws: SubmitChatModerationReportError.missingRoomContext) {
            try await useCase.submitUserReport(
                ChatUserReportCommand(
                    targetUserID: "user-2",
                    reason: .spam,
                    detail: nil,
                    roomID: nil,
                    triggerMessageID: "message-1",
                    clientRequestID: UUID()
                )
            )
        }
        #expect(repository.callCount == 0)
    }

    @Test
    func mapsMessageReportCallableContract() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [[
            "status": "alreadyReported",
            "submissionID": "submission-message",
            "deduplicated": false,
            "alreadyReported": true,
            "visibilityState": "visible",
            "seq": 42,
            "receivedAt": NSNull(),
            "originalReceivedAt": "2026-08-10T12:00:00.000Z"
        ]]
        let repository = CloudFunctionsChatModerationReportingRepository(transport: transport)
        let requestID = UUID(uuidString: "123E4567-E89B-42D3-A456-426614174000")!

        let receipt = try await repository.submitMessageReport(
            ChatMessageReportCommand(
                roomID: "room-1",
                messageID: "message-1",
                reason: .privacy,
                detail: "전화번호가 보여요",
                clientRequestID: requestID
            )
        )

        #expect(transport.calls.map(\.name) == ["submitMessageReport"])
        #expect(transport.calls[0].data["roomID"] as? String == "room-1")
        #expect(transport.calls[0].data["messageID"] as? String == "message-1")
        #expect(transport.calls[0].data["reason"] as? String == "privacy")
        #expect(receipt.status == .alreadyReported)
        #expect(receipt.isAlreadyReported)
        #expect(receipt.seq == 42)
    }
}

private final class ChatModerationReportingRepositoryFake:
    ChatModerationReportingRepositoryProtocol {
    private(set) var callCount = 0

    func submitMessageReport(
        _ command: ChatMessageReportCommand
    ) async throws -> ChatMessageReportReceipt {
        callCount += 1
        return ChatMessageReportReceipt(
            status: .accepted,
            submissionID: "unused",
            isDeduplicated: false,
            isAlreadyReported: false,
            visibilityState: "visible",
            seq: 1,
            receivedAt: Date(),
            originalReceivedAt: nil
        )
    }

    func submitUserReport(
        _ command: ChatUserReportCommand
    ) async throws -> ChatModerationReportReceipt {
        callCount += 1
        return ChatModerationReportReceipt(
            submissionID: "unused",
            isDeduplicated: false,
            receivedAt: Date()
        )
    }

    func submitRoomReport(
        _ command: ChatRoomReportCommand
    ) async throws -> ChatModerationReportReceipt {
        callCount += 1
        return ChatModerationReportReceipt(
            submissionID: "unused",
            isDeduplicated: false,
            receivedAt: Date()
        )
    }
}
