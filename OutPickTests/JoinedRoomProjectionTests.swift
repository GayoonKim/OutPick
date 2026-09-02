import Foundation
import Testing
@testable import OutPick

struct JoinedRoomProjectionTests {
    @Test func currentRoleAndReadFrontiersAreMapped() throws {
        let moderatorSince = Date(timeIntervalSince1970: 100)
        let projection = try #require(JoinedRoomProjection(
            documentID: "room-1",
            data: [
                "role": "moderator",
                "moderatorSince": moderatorSince,
                "lastReadSeq": 12,
                "lastReadUnreadMessageSeq": 8
            ]
        ))

        #expect(projection.role == .moderator)
        #expect(projection.moderatorSince == moderatorSince)
        #expect(projection.lastReadSeq == 12)
        #expect(projection.lastReadUnreadMessageSeq == 8)
    }

    @Test func legacyProjectionFallsBackUnreadFrontierToTimelineFrontier() throws {
        let projection = try #require(JoinedRoomProjection(
            documentID: "room-1",
            data: ["role": "member", "lastReadSeq": 11]
        ))

        #expect(projection.role == .member)
        #expect(projection.moderatorSince == nil)
        #expect(projection.lastReadUnreadMessageSeq == 11)
    }

    @Test func unknownRoleDoesNotEscalatePrivileges() throws {
        let projection = try #require(JoinedRoomProjection(
            documentID: "room-1",
            data: ["role": "future-admin"]
        ))

        #expect(projection.role == nil)
    }
}
