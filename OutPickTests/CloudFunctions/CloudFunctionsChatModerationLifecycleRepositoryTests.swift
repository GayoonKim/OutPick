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

    @Test
    func fetchMyRoomAccessMapsServerOnlyStatus() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [["status": "banned"]]
        let repository = CloudFunctionsChatModerationLifecycleRepository(
            transport: transport,
            currentUserID: { "member" }
        )

        let status = try await repository.fetchMyRoomAccess(roomID: "room-1")

        #expect(status == .banned)
        #expect(transport.calls.count == 1)
        #expect(transport.calls[0].name == "getMyRoomAccess")
        #expect(transport.calls[0].data["roomID"] as? String == "room-1")
    }

    @Test
    func roomRoleAccessRequiresRoleForActiveMember() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [["status": "member", "role": "moderator"]]
        let repository = CloudFunctionsChatModerationLifecycleRepository(
            transport: transport,
            currentUserID: { "moderator" }
        )

        let access = try await repository.fetchMyRoomRoleAccess(roomID: "room-1")

        #expect(access == ChatRoomRoleAccess(status: .member, role: .moderator))
        #expect(transport.calls[0].name == "getMyRoomAccess")
    }

    @Test
    func roomRoleMutationsMapCanonicalCallableContracts() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [
            [
                "roomID": "room-1", "subjectUID": "member-1", "role": "moderator",
                "moderatorCount": 1, "eventID": "event-1", "seq": 8,
                "deduplicated": false
            ],
            [
                "roomID": "room-1", "moderatorCount": 0, "memberCount": 2,
                "eventID": NSNull(), "seq": NSNull(), "mode": "left",
                "deduplicated": false
            ],
            [
                "roomID": "room-1", "moderatorCount": 0, "memberCount": 1,
                "eventID": "event-2", "seq": 9, "mode": "left",
                "ownerUID": "moderator-1", "deduplicated": true
            ]
        ]
        let repository = CloudFunctionsChatModerationLifecycleRepository(
            transport: transport,
            currentUserID: { "owner" }
        )

        let assigned = try await repository.assignModerator(
            roomID: "room-1",
            targetUID: "member-1"
        )
        let left = try await repository.leaveChatRoom(roomID: "room-1")
        let transferred = try await repository.transferOwnershipAndLeave(
            roomID: "room-1",
            successorUID: "moderator-1"
        )

        #expect(assigned.role == .moderator)
        #expect(assigned.eventID == "event-1")
        #expect(left.exitMode == .left)
        #expect(transferred.ownerUID == "moderator-1")
        #expect(transferred.isDeduplicated)
        #expect(transport.calls.map(\.name) == [
            "assignRoomModerator", "leaveChatRoom", "transferRoomOwnershipAndLeave"
        ])
        #expect(transport.calls[0].data["targetUID"] as? String == "member-1")
        #expect(transport.calls[2].data["successorUID"] as? String == "moderator-1")
        #expect(transport.calls.allSatisfy { $0.data["clientRequestID"] as? String != nil })
    }


    @Test
    func roomMemberRemovalAndBanManagementMapSafeCallableContracts() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [
            ["removed": true, "roomBanned": true, "memberCount": 3],
            [
                "items": [[
                    "banEntryToken": "token-1",
                    "reasonCode": "spam",
                    "displayNameSnapshot": "사용자",
                    "bannedAt": "2026-08-12T00:00:00.000Z"
                ]],
                "nextCursor": NSNull()
            ],
            ["roomBanned": false, "membershipRestored": false]
        ]
        let repository = CloudFunctionsChatModerationLifecycleRepository(
            transport: transport,
            currentUserID: { "owner" }
        )

        let receipt = try await repository.removeRoomMember(
            roomID: "room-1",
            targetUID: "member-1",
            reasonCode: "spam"
        )
        let page = try await repository.listRoomBans(
            roomID: "room-1",
            pageSize: 50,
            cursor: nil
        )
        try await repository.unbanRoomMember(
            roomID: "room-1",
            banEntryToken: "token-1"
        )

        #expect(receipt.memberCount == 3)
        #expect(page.items.map(\.token) == ["token-1"])
        #expect(page.items.first?.displayName == "사용자")
        #expect(transport.calls.map(\.name) == [
            "removeRoomMember", "listRoomBans", "unbanRoomMember"
        ])
        #expect(transport.calls[0].data["targetUID"] as? String == "member-1")
        #expect(transport.calls[2].data["banEntryToken"] as? String == "token-1")
    }
}
