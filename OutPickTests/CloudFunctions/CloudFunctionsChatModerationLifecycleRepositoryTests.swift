import Foundation
import Testing
@testable import OutPick

struct CloudFunctionsChatModerationLifecycleRepositoryTests {
    @Test
    func deleteMessageMapsServerAuthoritativeCallableContract() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [[
            "messageID": "message-1",
            "seq": 7,
            "isDeleted": true,
            "deduplicated": false
        ]]
        let repository = CloudFunctionsChatModerationLifecycleRepository(
            transport: transport,
            currentUserID: { "user-1" }
        )

        let receipt = try await repository.deleteMessage(
            roomID: "room-1",
            messageID: "message-1",
            expectedSeq: 7,
            reasonCode: "chatMessageDeletion"
        )

        #expect(transport.calls.count == 1)
        #expect(transport.calls[0].name == "deleteChatMessage")
        #expect(transport.calls[0].data["roomID"] as? String == "room-1")
        #expect(transport.calls[0].data["messageID"] as? String == "message-1")
        #expect(transport.calls[0].data["expectedSeq"] as? Int64 == 7)
        #expect(transport.calls[0].data["reasonCode"] as? String == "chatMessageDeletion")
        #expect(transport.calls[0].data["clientRequestID"] as? String != nil)
        #expect(receipt == ChatMessageDeletionReceipt(
            messageID: "message-1",
            seq: 7,
            isDeleted: true,
            isDeduplicated: false
        ))
    }

    @Test
    func closeOwnedRoomUsesLifecycleVersionAndReturnsClosedMode() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [[
            "lifecycleStatus": "closedByOwner",
            "lifecycleVersion": 4,
            "cleanupStatus": "pending"
        ]]
        let repository = CloudFunctionsChatModerationLifecycleRepository(
            transport: transport,
            currentUserID: { "owner" }
        )

        let result = try await repository.closeOwnedRoom(
            roomID: "room-1",
            expectedLifecycleVersion: 3
        )

        #expect(transport.calls[0].name == "closeOwnedChatRoom")
        #expect(transport.calls[0].data["expectedLifecycleVersion"] as? Int == 3)
        #expect(result == ChatRoomExitResult(roomID: "room-1", mode: .closed))
    }

    @Test
    func acknowledgeClosureUsesServerCallable() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [[
            "acknowledged": true,
            "deduplicated": false
        ]]
        let repository = CloudFunctionsChatModerationLifecycleRepository(
            transport: transport,
            currentUserID: { "member" }
        )

        try await repository.acknowledgeClosureNotice(roomID: "room-1")

        #expect(transport.calls.count == 1)
        #expect(transport.calls[0].name == "acknowledgeRoomClosure")
        #expect(transport.calls[0].data["roomID"] as? String == "room-1")
        #expect(transport.calls[0].data["clientRequestID"] as? String != nil)
    }
}
