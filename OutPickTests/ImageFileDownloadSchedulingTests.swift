import XCTest
import UIKit
@testable import OutPick

@MainActor
final class ImageFileDownloadSchedulingTests: XCTestCase {
    func testPreparedLocalStoreFinishesBeforeDiskWriteAndSurvivesCallerCancellation() async throws {
        let resources = resources()
        let memory = ImageCacheMemoryStore()
        let disk = ImageCacheDiskStore(folderName: "LocalPending-\(UUID())", resources: resources)
        let pipeline = ImageCachePipeline(fetcher: { _, _ in XCTFail("저장한 이미지를 다시 다운로드하면 안 됨"); return Data([1]) },
            memory: memory, disk: disk, resources: resources, decoder: { _ in UIImage() })
        let writer = try await resources.io.acquire(kind: .write)
        let prepared = expectation(description: "디스크 쓰기 전 메모리 준비 완료")
        let store = Task { try await pipeline.storeImageData(Data([1]), path: "local"); prepared.fulfill() }
        await fulfillment(of: [prepared], timeout: 3)
        XCTAssertNotNil(pipeline.cachedMemoryImageImmediately(path: "local"))
        store.cancel()
        await writer.release()
        _ = try await store.value
        await pipeline.flushPendingWrites()
        memory.removeAll()
        let cached = await pipeline.cachedImage(path: "local")
        XCTAssertNotNil(cached)
        await pipeline.removeAllCachedImages()
        await assertReleased(resources)
    }

    func testDeleteWhileLocalPreparationWaitsRejectsLateStore() async throws {
        let resources = resources()
        let disk = ImageCacheDiskStore(folderName: "LocalStale-\(UUID())", resources: resources)
        let pipeline = ImageCachePipeline(fetcher: { _, _ in Data([1]) }, disk: disk,
            resources: resources, decoder: { _ in UIImage() })
        let decode = try await resources.decode.acquire(2)
        let store = Task { try await pipeline.storeImageData(Data([1]), path: "deleted") }
        await eventually { await resources.decode.snapshot().waiting == 1 }
        await pipeline.removeImage(path: "deleted")
        await decode.release()
        do { try await store.value; XCTFail("삭제 후 늦은 저장은 거절해야 함") }
        catch { XCTAssertTrue(error is CancellationError) }
        await pipeline.flushPendingWrites()
        XCTAssertNil(pipeline.cachedMemoryImageImmediately(path: "deleted"))
        let cached = await pipeline.cachedImage(path: "deleted")
        XCTAssertNil(cached)
        await pipeline.removeAllCachedImages()
        await assertReleased(resources)
    }

    func testMemoryEvictionDuringPendingWriteReusesDiskWithoutDownloadingAgain() async throws {
        let resources = resources(downloads: 1)
        let memory = ImageCacheMemoryStore()
        let locations = FileTransferLocations()
        let disk = ImageCacheDiskStore(folderName: "PendingReuse-\(UUID())", resources: resources)
        let pipeline = ImageCachePipeline(fetcher: { _, _ in throw URLError(.unsupportedURL) },
            fileFetcher: { _, _, url in
                await locations.add(url)
                try Data([1]).write(to: url)
            }, memory: memory, disk: disk, resources: resources,
            decoder: { _ in UIImage() }, fileDecoder: { _ in UIImage() })
        let writer = try await resources.io.acquire(kind: .write)
        _ = try await pipeline.loadImage(path: "A", maxBytes: 100)
        memory.removeAll()
        let second = Task { try await pipeline.loadImage(path: "A", maxBytes: 100) }
        // 다른 키는 전역 flush에 막히지 않고 기존 디스크 파일을 조회할 수 있어야 한다.
        let unrelated = await pipeline.cachedImage(path: "absent")
        XCTAssertNil(unrelated)
        await writer.release()
        _ = try await second.value
        await pipeline.flushPendingWrites()
        let urls = await locations.urls
        XCTAssertEqual(urls.count, 1, "메모리 퇴거 후에도 pending 저장을 재사용해야 함")
        await pipeline.removeAllCachedImages()
        await assertReleased(resources)
    }

    func testSlowFileDoesNotBlockAnotherDownloadOrCacheWrite() async throws {
        let resources = resources()
        let gate = FileTransferBarrier()
        let aStarted = expectation(description: "A 시작")
        let bStarted = expectation(description: "A 완료 전 B 시작")
        let written = expectation(description: "전송 중 캐시 저장")
        let processor = processor(resources) { path, _, url in
            if path == "A" { aStarted.fulfill() } else { bStarted.fulfill() }
            await gate.wait()
            try Data([1]).write(to: url)
        }
        let disk = ImageCacheDiskStore(folderName: "FileScheduling-\(UUID())", resources: resources)
        let a = Task { try await processor.download(path: "A", maxBytes: 100) }
        await fulfillment(of: [aStarted], timeout: 3)
        let b = Task { try await processor.download(path: "B", maxBytes: 100) }
        let write = Task { await disk.write(data: Data([7]), forKey: "other"); written.fulfill() }
        await fulfillment(of: [bStarted, written], timeout: 3)
        await gate.open()
        let values = try await [a.value, b.value]
        for value in values { await value.release?() }
        await write.value
        let stored = await disk.read(forKey: "other")
        XCTAssertEqual(stored, Data([7]))
        await disk.removeAll()
        await assertReleased(resources)
    }

    func testSharedFileLimitAndDisplayBeforeBlockedPersistence() async throws {
        let resources = resources(downloads: 2)
        let writer = try await resources.io.acquire(kind: .write)
        let locations = FileTransferLocations()
        func pipeline() -> ImageCachePipeline {
            ImageCachePipeline(fetcher: { _, _ in throw URLError(.unsupportedURL) }, fileFetcher: { _, _, url in
                await locations.add(url)
                try Data([1]).write(to: url)
            }, disk: ImageCacheDiskStore(folderName: "FileScheduling-\(UUID())", resources: resources),
               resources: resources, decoder: { _ in UIImage() }, fileDecoder: { _ in UIImage() })
        }
        let first = pipeline(), second = pipeline()
        let displayed = expectation(description: "캐시 쓰기 대기 중 두 이미지 반환")
        displayed.expectedFulfillmentCount = 2
        let a = Task { let image = try await first.loadImage(path: "A", maxBytes: 100); displayed.fulfill(); return image }
        let b = Task { let image = try await second.loadImage(path: "B", maxBytes: 100); displayed.fulfill(); return image }
        await fulfillment(of: [displayed], timeout: 3)
        let files = await resources.files.snapshot()
        let network = await resources.network.snapshot()
        XCTAssertEqual(files.used, 2)
        XCTAssertEqual(network.active, 0)
        let urls = await locations.urls
        XCTAssertEqual(urls.count, 2)
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let c = Task { try await first.loadImage(path: "C", maxBytes: 100) }
        await eventually { await resources.files.snapshot().waiting == 1 }
        c.cancel()
        _ = await c.result
        await writer.release()
        _ = try await (a.value, b.value)
        await first.flushPendingWrites()
        await second.flushPendingWrites()
        await eventually { await resources.files.snapshot().used == 0 }
        await eventually { urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } }
        await first.removeAllCachedImages()
        await second.removeAllCachedImages()
        await assertReleased(resources)
    }

    func testCancellationRetainsPermitsUntilTransportAcknowledgesEnd() async throws {
        let resources = resources()
        let gate = FileTransferBarrier()
        let locations = FileTransferLocations()
        let started = expectation(description: "전송 시작")
        let cancelled = expectation(description: "전송 취소 요청")
        let processor = processor(resources) { _, _, url in
            await locations.add(url)
            try Data([1]).write(to: url)
            try await withTaskCancellationHandler {
                started.fulfill()
                await gate.wait()
                try Task.checkCancellation()
            } onCancel: { cancelled.fulfill() }
        }
        let task = Task { try await processor.download(path: "A", maxBytes: 100) }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        await fulfillment(of: [cancelled], timeout: 3)
        let network = await resources.network.snapshot()
        let files = await resources.files.snapshot()
        XCTAssertEqual(network.active, 1)
        XCTAssertEqual(files.used, 1)
        await gate.open()
        do { _ = try await task.value; XCTFail("취소 누락") } catch { XCTAssertTrue(error is CancellationError) }
        let urls = await locations.urls
        await eventually { urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } }
        await assertReleased(resources)
    }

    func testCancelledNetworkWaiterReturnsFileReservationWithoutStartingTransport() async throws {
        let resources = resources(downloads: 1)
        let network = try await resources.network.acquire()
        let processor = processor(resources) { _, _, _ in XCTFail("대기 중 취소된 전송 시작") }
        let task = Task { try await processor.download(path: "A", maxBytes: 100) }
        await eventually { await resources.network.snapshot().waiting == 1 }
        task.cancel()
        _ = await task.result
        let files = await resources.files.snapshot()
        XCTAssertEqual(files.used, 0)
        await network.release()
        await assertReleased(resources)
    }

    func testFileFailureOversizeAndInvalidDecodeCleanUpReservations() async throws {
        for mode in 0..<3 {
            let resources = resources()
            let locations = FileTransferLocations()
            let processor = ImagePipelineProcessor(resources: resources, fetcher: { _, _ in throw URLError(.unsupportedURL) }, fileFetcher: { _, _, url in
                await locations.add(url)
                try Data(repeating: 1, count: mode == 1 ? 101 : 1).write(to: url)
                if mode == 0 { throw URLError(.networkConnectionLost) }
            }, decoder: { _ in nil }, fileDecoder: { _ in nil })
            do { _ = try await processor.download(path: "A", maxBytes: 100); XCTFail("오류 누락") } catch {}
            let urls = await locations.urls
            XCTAssertEqual(urls.count, 1)
            await eventually { urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } }
            await assertReleased(resources)
        }
    }

    func testCancellationWhileWaitingForFileDecodeReleasesFile() async throws {
        let resources = resources()
        let decode = try await resources.decode.acquire(2)
        let locations = FileTransferLocations()
        let processor = processor(resources) { _, _, url in
            await locations.add(url)
            try Data([1]).write(to: url)
        }
        let task = Task { try await processor.download(path: "A", maxBytes: 100) }
        await eventually { await resources.decode.snapshot().waiting == 1 }
        let network = await resources.network.snapshot()
        XCTAssertEqual(network.active, 0)
        task.cancel()
        _ = await task.result
        await decode.release()
        let urls = await locations.urls
        await eventually { urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } }
        await assertReleased(resources)
    }

    func testDiskWriteFailurePreservesDisplayAndReleasesFileThenRecovers() async throws {
        let resources = resources(downloads: 1)
        let locations = FileTransferLocations()
        let folder = "FileScheduling-FailedWrite-\(UUID())"
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(folder)
        // 디렉터리 대신 파일을 두어 실제 캐시 복사가 실패하도록 한다.
        try Data([9]).write(to: base)
        defer { try? FileManager.default.removeItem(at: base) }
        let disk = ImageCacheDiskStore(folderName: folder, resources: resources)
        let pipeline = ImageCachePipeline(fetcher: { _, _ in throw URLError(.unsupportedURL) },
            fileFetcher: { _, _, url in
                await locations.add(url)
                try Data([1]).write(to: url)
            }, disk: disk, resources: resources,
            decoder: { _ in UIImage() }, fileDecoder: { _ in UIImage() })

        let displayed = try await pipeline.loadImage(path: "A", maxBytes: 100)
        await pipeline.flushPendingWrites()
        XCTAssertTrue(pipeline.cachedMemoryImageImmediately(path: "A") === displayed)
        let absent = await disk.read(forKey: "imageCache|A")
        XCTAssertNil(absent)
        XCTAssertEqual(try Data(contentsOf: base), Data([9]))
        let firstURLs = await locations.urls
        XCTAssertEqual(firstURLs.count, 1)
        await eventually { firstURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } }
        await assertReleased(resources)

        _ = try await pipeline.loadImage(path: "A", maxBytes: 100)
        let afterMemoryHit = await locations.urls
        XCTAssertEqual(afterMemoryHit.count, 1, "저장 실패 후에도 메모리 이미지는 다시 다운로드하지 않음")

        // 저장소를 정상화하면 같은 슬롯으로 다음 파일의 다운로드와 저장이 진행돼야 한다.
        try FileManager.default.removeItem(at: base)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        _ = try await pipeline.loadImage(path: "B", maxBytes: 100)
        await pipeline.flushPendingWrites()
        let stored = await disk.read(forKey: "imageCache|B")
        XCTAssertEqual(stored, Data([1]))
        let allURLs = await locations.urls
        XCTAssertEqual(allURLs.count, 2)
        await eventually { allURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } }
        await assertReleased(resources)
    }

    private func resources(downloads: Int = 2) -> ImagePipelineResources {
        ImagePipelineResources(limits: ImagePipelineLimits(downloads: downloads, decodeBytes: 1, writeBytes: 1))
    }

    private func processor(_ resources: ImagePipelineResources, fetch: @escaping ImagePipelineProcessor.FileFetcher) -> ImagePipelineProcessor {
        ImagePipelineProcessor(resources: resources, fetcher: { _, _ in throw URLError(.unsupportedURL) }, fileFetcher: fetch,
                               decoder: { _ in UIImage() }, fileDecoder: { _ in UIImage() })
    }

    private func eventually(file: StaticString = #filePath, line: UInt = #line, _ predicate: () async -> Bool) async {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while ProcessInfo.processInfo.systemUptime < deadline {
            if await predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("제한 시간 내 예상 상태에 도달하지 못함", file: file, line: line)
    }

    private func assertReleased(_ resources: ImagePipelineResources, file: StaticString = #filePath, line: UInt = #line) async {
        for gate in [resources.network, resources.files, resources.decode, resources.io, resources.decodeBytes, resources.writeBytes] {
            let state = await gate.snapshot()
            XCTAssertEqual(state.used, 0, file: file, line: line)
            XCTAssertEqual(state.waiting, 0, file: file, line: line)
        }
    }
}

private actor FileTransferBarrier {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor FileTransferLocations {
    private(set) var urls: [URL] = []
    func add(_ url: URL) { urls.append(url) }
}
