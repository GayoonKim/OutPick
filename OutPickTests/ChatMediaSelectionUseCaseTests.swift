import Foundation
import Testing
@testable import OutPick

struct ChatMediaSelectionUseCaseTests {
    @Test func qaWithoutOverridesKeepsProductionPipelineDefaults() {
        for environment in [[:], ["OUTPICK_MEDIA_QA": "1"],
                            ["OUTPICK_MEDIA_QA": "1", "OUTPICK_MEDIA_QA_PREPARATION": "invalid"]] {
            let limits = ChatMediaPipelineLimits.configured(environment: environment, bundleIdentifier: "GayoonKim.OutPick.dev")
            #expect(limits.acquisition == 4)
            #expect(limits.imagePreparation == Int.max)
            #expect(limits.filesPerBatch == 4)
            #expect(limits.videoPreparation == 1)
        }
    }

    @Test func qaOverridesRequireOptInAndDevelopmentBundle() {
        let overrides = ["OUTPICK_MEDIA_QA": "1", "OUTPICK_MEDIA_QA_ACQUISITION": "all",
                         "OUTPICK_MEDIA_QA_PREPARATION": "4", "OUTPICK_MEDIA_QA_UPLOADS": "all"]
        let enabled = ChatMediaPipelineLimits.configured(environment: overrides, bundleIdentifier: "GayoonKim.OutPick.dev")
        #if DEBUG
        #expect(enabled.acquisition == Int.max)
        #expect(enabled.imagePreparation == 4)
        #expect(enabled.filesPerBatch == Int.max)
        #else
        #expect(enabled.acquisition == 4 && enabled.imagePreparation == Int.max && enabled.filesPerBatch == 4)
        #endif
        let production = ChatMediaPipelineLimits.configured(environment: overrides, bundleIdentifier: "GayoonKim.OutPick")
        var disabledEnvironment = overrides
        disabledEnvironment["OUTPICK_MEDIA_QA"] = "0"
        let disabled = ChatMediaPipelineLimits.configured(environment: disabledEnvironment, bundleIdentifier: "GayoonKim.OutPick.dev")
        for limits in [production, disabled] {
            #expect(limits.acquisition == 4 && limits.imagePreparation == Int.max && limits.filesPerBatch == 4)
        }
    }

    @Test func cancellationDuringPreparationRemovesTemporaryFileButKeepsOriginal() async throws {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let selection = try await fixture.useCase.acquire(sourceCount: 1, roomID: "room", senderUID: "sender", id: "cancel-parent") { index, directory in
            let url = directory.appendingPathComponent("source.jpg")
            try Data([7]).write(to: url)
            return .init(index: index, path: url.path, isVideo: false)
        }
        let preparedURL = fixture.root.appendingPathComponent("prepared.jpg")
        let cancellation = PreparationParentCancellation()
        let useCase = ChatMediaSelectionUseCase(repository: fixture.repository, prepareImage: { _, index in
            try Data([8]).write(to: preparedURL)
            cancellation.cancelParent()
            return ProcessedImage(index: index, originalFileURL: preparedURL, thumbData: Data(),
                                  originalWidth: 10, originalHeight: 10, bytesOriginal: 1, sha256: "prepared")
        })
        let task = Task {
            try await useCase.process(selection, onChunk: { _, _ in
                Issue.record("준비 도중 취소된 묶음은 공개하면 안 됩니다.")
            }, onCommitted: { _ in Issue.record("취소 뒤 원장 소유권을 이전하면 안 됩니다.") })
        }
        cancellation.install(task)
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: preparedURL.path))
        #expect(try Data(contentsOf: URL(fileURLWithPath: selection.selectionSources[0].path)) == Data([7]))
        #expect(try await fixture.repository.load(selection.selectionID)?.selectionSources.count == 1)
    }

    @Test(arguments: [4, Int.max]) func acquisitionPublishesOnlyAfterEveryOriginalIsOwned(width: Int) async throws {
        let fixture = Fixture(acquisition: width)
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

    @Test(arguments: [4, Int.max]) func acquisitionFailureRemovesJournalAndPartiallyCopiedFiles(width: Int) async throws {
        let fixture = Fixture(acquisition: width)
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

    @Test func failedPreparationIsPreservedSeparatelyAndRemainingOrderPreserved() async throws {
        let fixture = Fixture(failingIndex: 4)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let selection = fixture.selection(count: 35)
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        try Data([4]).write(to: URL(fileURLWithPath: selection.selectionSources[4].path))
        try await fixture.repository.save(selection)
        let emitted = ChunkRecorder()
        let rejected = try await fixture.useCase.process(selection, onChunk: { id, chunk in
            if case .failedImages(let sources) = chunk {
                try await fixture.useCase.preserveFailedImages(sources, id: id, roomID: "room", senderUID: "sender")
                return
            }
            guard case .images(let pairs) = chunk else { return }
            await emitted.record(pairs)
            try await fixture.persistence.saveOutgoingOutboxRecord(.init(messageID: id, roomID: "room", kind: .images,
                stage: .needsUpload, createdAt: Date(), updatedAt: Date(), localPayloadJSON: "{}", uploadedPayloadJSON: nil, lastError: nil))
        }, onCommitted: { _ in })
        #expect(rejected == 1)
        #expect(await emitted.counts == [30, 4])
        #expect(await emitted.hashes == (0..<35).filter { $0 != 4 }.map(String.init))
        let restored = try await fixture.repository.restored(roomID: "room", senderUID: "sender")
        #expect(restored.count == 1)
        #expect(restored[0].selectionSources.map(\.index) == [4])
        #expect(try Data(contentsOf: URL(fileURLWithPath: restored[0].selectionSources[0].path)) == Data([4]))
        #expect(try await fixture.repository.load(selection.selectionID) == nil)
    }

    @Test func oneFailedImageSurvivesRetryAndCanBeDeleted() async throws {
        let fixture = Fixture(failingIndex: 0)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let original = try await fixture.useCase.acquire(sourceCount: 1, roomID: "room", senderUID: "sender", id: "original") { index, directory in
            let url = directory.appendingPathComponent("source.jpg")
            try Data([9]).write(to: url)
            return .init(index: index, path: url.path, isVideo: false)
        }
        func process(_ selection: ChatMediaSelection) async throws {
            let failed = try await fixture.useCase.process(selection, onChunk: { id, chunk in
                guard case .failedImages(let sources) = chunk else { Issue.record("실패 묶음이어야 합니다."); return }
                try await fixture.useCase.preserveFailedImages(sources, id: id, roomID: "room", senderUID: "sender")
            }, onCommitted: { _ in })
            #expect(failed == 1)
        }
        try await process(original)
        let first = try #require(try await fixture.repository.restored(roomID: "room", senderUID: "sender").first)
        try await process(first)
        let restored = try await fixture.repository.restored(roomID: "room", senderUID: "sender")
        #expect(restored.count == 1)
        let retry = try #require(restored.first)
        #expect(try Data(contentsOf: URL(fileURLWithPath: retry.selectionSources[0].path)) == Data([9]))
        #expect(!FileManager.default.fileExists(atPath: first.selectionSources[0].path))
        try await fixture.useCase.deleteSelection(retry.selectionID)
        #expect(try await fixture.repository.restored(roomID: "room", senderUID: "sender").isEmpty)
        #expect(!FileManager.default.fileExists(atPath: retry.selectionSources[0].path))
    }

    @Test func failedChildSaveLeavesParentSourceRecoverable() async throws {
        let fixture = Fixture(failingIndex: 0)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let selection = try await fixture.useCase.acquire(sourceCount: 1, roomID: "room", senderUID: "sender", id: "parent") { index, directory in
            let url = directory.appendingPathComponent("source.jpg")
            try Data([7]).write(to: url)
            return .init(index: index, path: url.path, isVideo: false)
        }
        await #expect(throws: (any Error).self) {
            _ = try await fixture.useCase.process(selection, onChunk: { _, _ in
                throw CocoaError(.fileWriteOutOfSpace)
            }, onCommitted: { _ in })
        }
        let restored = try await fixture.repository.restored(roomID: "room", senderUID: "sender")
        #expect(restored.count == 1)
        #expect(restored[0].selectionID == selection.selectionID)
        #expect(try Data(contentsOf: URL(fileURLWithPath: restored[0].selectionSources[0].path)) == Data([7]))
    }

    @Test func thirtyOneFailedImagesRestoreAsThirtyAndOne() async throws {
        let fixture = Fixture(failsAll: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let selection = try await fixture.useCase.acquire(sourceCount: 31, roomID: "room", senderUID: "sender", id: "failed-parent") { index, directory in
            let url = directory.appendingPathComponent("\(index).jpg")
            try Data([UInt8(index)]).write(to: url)
            return .init(index: index, path: url.path, isVideo: false)
        }
        let count = try await fixture.useCase.process(selection, onChunk: { id, chunk in
            guard case .failedImages(let sources) = chunk else { Issue.record("실패 묶음이어야 합니다."); return }
            try await fixture.useCase.preserveFailedImages(sources, id: id, roomID: "room", senderUID: "sender")
        }, onCommitted: { _ in })
        #expect(count == 31)
        let restored = try await fixture.repository.restored(roomID: "room", senderUID: "sender")
        #expect(restored.map { $0.selectionSources.count } == [30, 1])
        #expect(restored.flatMap(\.selectionSources).map(\.index) == Array(0..<31))
        #expect(try await fixture.repository.load(selection.selectionID) == nil)
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
        init(failingIndex: Int? = nil, failsAll: Bool = false, acquisition: Int = 4) {
            repository = ChatMediaSelectionRepository(persistence: persistence, root: root)
            useCase = ChatMediaSelectionUseCase(repository: repository, limits: ChatMediaPipelineLimits(acquisition: acquisition), prepareImage: { url, index in
                if failsAll || index == failingIndex { throw MediaError.failedToConvertImage }
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

// 준비 콜백 안에서 부모를 취소하여 실제 파일 생성과 취소의 순서를 고정한다.
private final class PreparationParentCancellation: @unchecked Sendable {
    private let installed = DispatchSemaphore(value: 0)
    private var parent: Task<Int, Error>?
    func install(_ task: Task<Int, Error>) {
        parent = task
        installed.signal()
    }
    func cancelParent() {
        installed.wait()
        parent?.cancel()
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
