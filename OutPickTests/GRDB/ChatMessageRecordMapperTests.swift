import Testing
@testable import OutPick

struct ChatMessageRecordMapperTests {
    @Test func messageRecordRoundTripSortsAttachments() throws {
        let second = Attachment(type: .image, index: 2, pathThumb: "t2", pathOriginal: "o2", width: 2, height: 2, bytesOriginal: 2, hash: "h2", blurhash: nil, duration: nil)
        let first = Attachment(type: .image, index: 1, pathThumb: "t1", pathOriginal: "o1", width: 1, height: 1, bytesOriginal: 1, hash: "h1", blurhash: nil, duration: nil)
        let message = GRDBTestFixtures.message(attachments: [second, first])

        let record = try #require(ChatMessageRecordMapper.record(from: message))
        let restored = try ChatMessageRecordMapper.message(from: record)

        #expect(restored.ID == message.ID)
        #expect(restored.attachments.map(\.index) == [1, 2])
    }

    @Test func invalidRequiredIdentifiersAreSkipped() {
        let invalid = GRDBTestFixtures.message(roomID: "")
        #expect(ChatMessageRecordMapper.record(from: invalid) == nil)
    }
}
