import Foundation
import Testing
@testable import OutPick

struct ChatRoomParticipantRolePolicyTests {
    @Test func ordersCurrentUserThenOwnerModeratorsAndMembers() {
        let older = Date(timeIntervalSince1970: 10)
        let newer = Date(timeIntervalSince1970: 20)
        let values = [
            participant("member-b", role: .member),
            participant("moderator-new", role: .moderator, moderatorSince: newer),
            participant("owner", role: .owner),
            participant("me", role: .member),
            participant("moderator-old", role: .moderator, moderatorSince: older),
            participant("member-a", role: .member)
        ]

        let sorted = ChatRoomParticipantOrdering.sorted(
            values,
            currentUserID: "me",
            ownerUID: "owner"
        )

        #expect(sorted.map(\.userID) == [
            "me", "owner", "moderator-old", "moderator-new", "member-a", "member-b"
        ])
    }

    @Test func pinnedModeratorWinsOverDuplicateLegacyMemberPageEntry() {
        let values = [
            participant("moderator", role: .moderator, moderatorSince: Date(timeIntervalSince1970: 10)),
            participant("moderator", role: .member),
            participant("member", role: .member)
        ]

        let result = ChatRoomParticipantOrdering.deduplicatedAndSorted(
            values,
            currentUserID: "me",
            ownerUID: "owner"
        )

        #expect(result.map(\.userID) == ["moderator", "member"])
        #expect(result.first?.role == .moderator)
    }

    @Test func ownerCanAssignMembersAndRevokeModeratorsButCannotActOnOwner() {
        #expect(ChatRoomParticipantActionPolicy.actions(
            actorRole: .owner,
            actorUserID: "owner",
            target: participant("member", role: .member),
            isEnabled: true
        ) == [.assignModerator, .removeFromRoom])
        #expect(ChatRoomParticipantActionPolicy.actions(
            actorRole: .owner,
            actorUserID: "owner",
            target: participant("moderator", role: .moderator),
            isEnabled: true
        ) == [.revokeModerator, .removeFromRoom])
        #expect(ChatRoomParticipantActionPolicy.actions(
            actorRole: .owner,
            actorUserID: "owner",
            target: participant("owner", role: .owner),
            isEnabled: true
        ).isEmpty)
    }

    @Test func moderatorCanOnlyRemoveOrdinaryMembersOrResignSelf() {
        #expect(ChatRoomParticipantActionPolicy.actions(
            actorRole: .moderator,
            actorUserID: "me",
            target: participant("member", role: .member),
            isEnabled: true
        ) == [.removeFromRoom])
        #expect(ChatRoomParticipantActionPolicy.actions(
            actorRole: .moderator,
            actorUserID: "me",
            target: participant("me", role: .moderator),
            isEnabled: true
        ) == [.resignModerator])
        #expect(ChatRoomParticipantActionPolicy.actions(
            actorRole: .moderator,
            actorUserID: "me",
            target: participant("other-moderator", role: .moderator),
            isEnabled: true
        ).isEmpty)
        #expect(ChatRoomParticipantActionPolicy.actions(
            actorRole: .moderator,
            actorUserID: "me",
            target: participant("owner", role: .owner),
            isEnabled: true
        ).isEmpty)
    }

    @Test func cachedOrOfflineStateDisablesEveryAction() {
        #expect(ChatRoomParticipantActionPolicy.actions(
            actorRole: .owner,
            actorUserID: "owner",
            target: participant("member", role: .member),
            isEnabled: false
        ).isEmpty)
    }

    @Test func rolloutOffHidesOnlyNewAssignmentAndKeepsExistingSafetyActions() {
        #expect(ChatRoomParticipantActionPolicy.actions(
            actorRole: .owner,
            actorUserID: "owner",
            target: participant("member", role: .member),
            isEnabled: true,
            isModeratorDelegationEnabled: false
        ) == [.removeFromRoom])
        #expect(ChatRoomParticipantActionPolicy.actions(
            actorRole: .owner,
            actorUserID: "owner",
            target: participant("moderator", role: .moderator),
            isEnabled: true,
            isModeratorDelegationEnabled: false
        ) == [.revokeModerator, .removeFromRoom])
    }

    @Test func mapsStableServerCodesWithoutExposingRawValue() {
        let error = NSError(
            domain: "FunctionsErrorDomain",
            code: 9,
            userInfo: ["details": ["errorCode": "TARGET_ALREADY_MODERATOR"]]
        )

        #expect(ChatRoomRoleMutationErrorMessage.serverErrorCode(from: error) == "TARGET_ALREADY_MODERATOR")
        #expect(ChatRoomRoleMutationErrorMessage.message(for: error) == "이미 관리자인 사용자예요.")
        let rolloutError = NSError(
            domain: "FunctionsErrorDomain",
            code: 9,
            userInfo: ["details": ["errorCode": "FEATURE_NOT_AVAILABLE"]]
        )
        #expect(ChatRoomRoleMutationErrorMessage.message(for: rolloutError) ==
            "채팅방 관리자 기능을 준비 중이에요.")
        #expect(ChatRoomRoleMutationErrorMessage.message(for: NSError(domain: "test", code: 1)) ==
            "잠시 후 다시 시도해 주세요.")
    }

    private func participant(
        _ userID: String,
        role: ChatRoomMemberRole,
        moderatorSince: Date? = nil
    ) -> ChatRoomParticipant {
        ChatRoomParticipant(
            user: LocalChatUser(userID: userID, nickname: userID, profileImagePath: nil),
            role: role,
            moderatorSince: moderatorSince
        )
    }
}
