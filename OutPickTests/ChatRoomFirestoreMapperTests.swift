//
//  ChatRoomFirestoreMapperTests.swift
//  OutPickTests
//
//  Created by Codex on 7/14/26.
//

import Foundation
import Testing
@testable import OutPick

struct ChatRoomFirestoreMapperTests {
    @Test func documentIDWinsOverLegacyStoredID() throws {
        let dto = try decodeDTO("""
        {
          "ID": "stale-stored-id",
          "id": "another-stale-id",
          "roomName": "Room",
          "creatorUID": "owner-1",
          "createdAt": "2026-07-14T00:00:00Z"
        }
        """)

        let room = try ChatRoomFirestoreMapper.map(dto: dto, documentID: "path-room-id")

        #expect(room.id == "path-room-id")
    }

    @Test func missingAncillaryFieldsUseCompatibilityDefaults() throws {
        let dto = try decodeDTO("""
        {
          "roomName": "Legacy Room",
          "creatorUID": "owner-1",
          "createdAt": "2026-07-14T00:00:00Z"
        }
        """)

        let room = try ChatRoomFirestoreMapper.map(dto: dto, documentID: "room-1")

        #expect(room.roomDescription == "")
        #expect(room.participants.isEmpty)
        #expect(room.memberCount == 0)
        #expect(room.seq == 0)
        #expect(room.isClosed == false)
    }

    @Test func emptyCoreIdentityFieldsFailMapping() throws {
        let emptyName = try decodeDTO("""
        {"roomName":" ","creatorUID":"owner-1","createdAt":"2026-07-14T00:00:00Z"}
        """)
        let emptyCreator = try decodeDTO("""
        {"roomName":"Room","creatorUID":" ","createdAt":"2026-07-14T00:00:00Z"}
        """)

        #expect(throws: ChatRoomFirestoreMappingError.missingDocumentID) {
            try ChatRoomFirestoreMapper.map(dto: emptyName, documentID: " ")
        }
        #expect(throws: ChatRoomFirestoreMappingError.emptyRoomName) {
            try ChatRoomFirestoreMapper.map(dto: emptyName, documentID: "room-1")
        }
        #expect(throws: ChatRoomFirestoreMappingError.emptyCreatorUID) {
            try ChatRoomFirestoreMapper.map(dto: emptyCreator, documentID: "room-1")
        }
    }

    @Test func missingOrWrongTypedCoreFieldsFailDecoding() {
        #expect(throws: (any Error).self) {
            try decodeDTO("""
            {"creatorUID":"owner-1","createdAt":"2026-07-14T00:00:00Z"}
            """)
        }
        #expect(throws: (any Error).self) {
            try decodeDTO("""
            {"roomName":"Room","createdAt":"2026-07-14T00:00:00Z"}
            """)
        }
        #expect(throws: (any Error).self) {
            try decodeDTO("""
            {"roomName":"Room","creatorUID":"owner-1"}
            """)
        }
        #expect(throws: (any Error).self) {
            try decodeDTO("""
            {"roomName":42,"creatorUID":"owner-1","createdAt":"2026-07-14T00:00:00Z"}
            """)
        }
        #expect(throws: (any Error).self) {
            try decodeDTO("""
            {"roomName":"Room","creatorUID":"owner-1","createdAt":"2026-07-14T00:00:00Z","memberCount":"one"}
            """)
        }
    }

    @Test func creationPayloadExcludesAllDocumentIdentityAndLegacyParticipantFields() {
        let room = ChatRoom(
            id: "room-1",
            roomName: "Minimal Room",
            roomDescription: "Description",
            participants: ["owner-1"],
            creatorUID: "owner-1",
            createdAt: Date(timeIntervalSince1970: 100),
            memberCount: 1
        )

        let payload = ChatRoomFirestoreMapper.creationData(from: room)

        #expect(payload["ID"] == nil)
        #expect(payload["id"] == nil)
        #expect(payload["participantUIDs"] == nil)
        #expect(payload["creatorUID"] as? String == "owner-1")
        #expect(payload["memberCount"] as? Int == 1)
        #expect(payload["roomSearchIndexVersion"] != nil)
    }

    private func decodeDTO(_ json: String) throws -> ChatRoomFirestoreDTO {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ChatRoomFirestoreDTO.self, from: Data(json.utf8))
    }
}
