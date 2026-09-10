import Foundation
import Testing
@testable import OutPick

struct ChatMediaSelectionUseCaseTests {
    @Test func acquisitionPublishesOnlyAfterEveryOriginalIsOwned() async throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let id = UUID().uuidString
        let selection = try await fixture.useCase.acquire(sourceCount: 9, roomID: "room", senderUID: "sender", id: id) { index, directory in
            #expect(try await fixture.repository.load(id)?.selectionSources.isEmpty == true)
            let path = directory.appendingPathComponent("\(index).jpg")
            try Data([UInt8(index)]).write(to: path)
            return .init(index: index, path: path.path, isVideo: false)
        }
        #expect(selection.selectionSources.map(\.index) == Array(0..<9))
        #expect(try await fixture.repository.load(id)?.selectionSources.count == 9)
    }

    @Test func acquisitionFailureRemovesJournalAndPartiallyCopiedFiles() async throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let id = UUID().uuidString
        await #expect(throws: (any Error).self) {
            _ = try await fixture.useCase.acquire(sourceCount: 9, roomID: "room", senderUID: "sender", id: id) { index, directory in
                let path = directory.appendingPathComponent("\(index).jpg")
                try Data([0]).write(to: path)
                if index == 5 { throw MediaError.failedToConvertImage }
                return .init(index: index, path: path.path, isVideo: false)
            }
        }
        #expect(try await fixture.repository.load(id) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(id).path))
    }

    @Test func seventySourcesBecomeThirtyThirtyTenWithoutRepresentative() async throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let selection = fixture.selection(count: 70)
        try await fixture.repository.save(selection)
        let emitted = ChunkRecorder()
        let rejected = try await fixture.useCase.process(selection, onChunk: { id, chunk in
            guard case .images(let pairs) = chunk else { Issue.record("이미지 묶음이어야 합니다."); return }
            await emitted.record(pairs)
            try await fixture.persistence.saveOutgoingOutboxRecord(.init(messageID: id, roomID: "room", kind: .images,
                stage: .needsUpload, createdAt: Date(), updatedAt: Date(), localPayloadJSON: "{}", uploadedPayloadJSON: nil, lastError: nil))
        }, onCommitted: { _ in })
        #expect(rejected == 0)
        #expect(await emitted.counts == [30, 30, 10])
        #expect(await emitted.hashes == (0..<70).map(String.init))
        #expect(try await fixture.repository.load(selection.selectionID) == nil)
    }

    @Test func failedPreparationIsExcludedAndRemainingOrderPreserved() async throws {
        let fixture = Fixture(failingIndex: 4)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let selection = fixture.selection(count: 35)
        try await fixture.repository.save(selection)
        let emitted = ChunkRecorder()
        let rejected = try await fixture.useCase.process(selection, onChunk: { id, chunk in
            guard case .images(let pairs) = chunk else { return }
            await emitted.record(pairs)
            try await fixture.persistence.saveOutgoingOutboxRecord(.init(messageID: id, roomID: "room", kind: .images,
                stage: .needsUpload, createdAt: Date(), updatedAt: Date(), localPayloadJSON: "{}", uploadedPayloadJSON: nil, lastError: nil))
        }, onCommitted: { _ in })
        #expect(rejected == 1)
        #expect(await emitted.counts == [30, 4])
        #expect(await emitted.hashes == (0..<35).filter { $0 != 4 }.map(String.init))
    }

    @Test func interruptedParentConsumesDurableChildBeforeRestoringRemainder() async throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var selection = fixture.selection(count: 70)
        selection.pendingChunk = .init(messageID: "child", indices: Array(0..<30))
        try await fixture.repository.save(selection)
        try await fixture.persistence.saveOutgoingOutboxRecord(.init(messageID: "child", roomID: "room", kind: .images,
            stage: .needsUpload, createdAt: Date(), updatedAt: Date(), localPayloadJSON: "{}", uploadedPayloadJSON: nil, lastError: nil))
        let restored = try await fixture.repository.restored(roomID: "room", senderUID: "sender")
        #expect(restored.count == 1)
        #expect(restored.first?.selectionSources.map(\.index) == Array(30..<70))
        #expect(restored.first?.pendingChunk == nil)
        #expect(try await fixture.repository.restored(roomID: "room", senderUID: "other").isEmpty)
    }

    private struct Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let persistence = SelectionTestPersistence()
        let repository: ChatMediaSelectionRepository
        let useCase: ChatMediaSelectionUseCase
        init(failingIndex: Int? = nil) {
            repository = ChatMediaSelectionRepository(persistence: persistence, root: root)
            useCase = ChatMediaSelectionUseCase(repository: repository, prepareImage: { url, index in
                if index == failingIndex { throw MediaError.failedToConvertImage }
                return ProcessedImage(index: index, originalFileURL: url, thumbData: Data(),
                    originalWidth: 10, originalHeight: 10, bytesOriginal: 100, sha256: String(index))
            })
        }
        func selection(count: Int) -> ChatMediaSelection {
            .init(selectionID: UUID().uuidString, roomID: "room", senderUID: "sender", createdAt: Date(),
                selectionSources: (0..<count).map { .init(index: $0, path: root.appendingPathComponent("\($0).jpg").path, isVideo: false) })
        }
    }
}

private actor ChunkRecorder {
    var counts: [Int] = []
    var hashes: [String] = []
    func record(_ pairs: [ProcessedImage]) {
        counts.append(pairs.count)
        hashes.append(contentsOf: pairs.map(\.sha256))
    }
}

private actor SelectionTestPersistence: ChatOutgoingOutboxPersisting {
    private var records: [String: ChatOutgoingOutboxRecord] = [:]
    func saveOutgoingOutboxRecord(_ record: ChatOutgoingOutboxRecord) async throws { records[record.messageID] = record }
    func fetchOutgoingOutboxRecord(messageID: String) async throws -> ChatOutgoingOutboxRecord? { records[messageID] }
    func fetchOutgoingOutboxRecords(messageIDs: [String]) async throws -> [ChatOutgoingOutboxRecord] { messageIDs.compactMap { records[$0] } }
    func fetchOutgoingOutboxRecords(roomID: String) async throws -> [ChatOutgoingOutboxRecord] { records.values.filter { $0.roomID == roomID } }
    func deleteOutgoingOutboxRecord(messageID: String) async throws { records.removeValue(forKey: messageID) }
    func deleteOutgoingOutboxRecords(messageIDs: [String]) async throws { messageIDs.forEach { records.removeValue(forKey: $0) } }
    func deleteOutgoingOutboxRecords(roomID: String) async throws { records = records.filter { $0.value.roomID != roomID } }
}
