import Foundation
import Testing
import UIKit
@testable import OutPick

struct ImagePipelineResourcesTests {
    @Test func cancelledWaiterDoesNotLeakAndDoubleReleaseIsHarmless() async throws {
        let gate = ImageStageGate(2, name: "test")
        let held = try await gate.acquire(2)
        let waiting = Task { try await gate.acquire() }
        try await waitUntil { await gate.snapshot().waiting == 1 }
        waiting.cancel()
        do { _ = try await waiting.value; Issue.record("취소된 대기가 성공했습니다.") }
        catch { #expect(error is CancellationError) }
        #expect(await gate.snapshot().used == 2)
        await held.release()
        await held.release()
        #expect(await gate.snapshot().used == 0)
        #expect(await gate.snapshot().waiting == 0)
    }

    @Test func promotionChangesQueuedOrderWithoutRestartingWork() async throws {
        let gate = ImageStageGate(1, name: "test")
        let held = try await gate.acquire()
        let first = Task { try await gate.acquire(context: ImageWorkContext(.prefetch)) }
        try await waitUntil { await gate.snapshot().waiting == 1 }
        let promoted = ImageWorkContext(.prefetch)
        let second = Task { try await gate.acquire(context: promoted) }
        try await waitUntil { await gate.snapshot().waiting == 2 }
        promoted.update(.visible)
        await held.release()
        let secondLease = try await second.value
        #expect(await gate.snapshot().waiting == 1)
        await secondLease.release()
        let firstLease = try await first.value
        await firstLease.release()
        #expect(await gate.snapshot().active == 0)
    }

    @Test func diskHasTotalLimitAndSingleWriter() async throws {
        let gate = ImageStageGate(2, name: "test", maxWrites: 1)
        let write = try await gate.acquire(kind: .write)
        let read = try await gate.acquire(kind: .read)
        let nextWrite = Task { try await gate.acquire(kind: .write) }
        try await waitUntil { await gate.snapshot().waiting == 1 }
        #expect(await gate.snapshot().active == 2)
        await read.release()
        #expect(await gate.snapshot().waiting == 1)
        #expect(await gate.snapshot().writes == 1)
        await write.release()
        let next = try await nextWrite.value
        await next.release()
        #expect(await gate.snapshot().used == 0)
    }

    @Test func reducedReservationAdmitsWaitingWorkAndOversizeFailsImmediately() async throws {
        let gate = ImageStageGate(8, name: "test")
        let first = try await gate.acquire(8)
        let next = Task { try await gate.acquire(6) }
        try await waitUntil { await gate.snapshot().waiting == 1 }
        await first.reduce(to: 2)
        let second = try await next.value
        #expect(await gate.snapshot().used == 8)
        do { _ = try await gate.acquire(9); Issue.record("용량보다 큰 예약이 성공했습니다.") }
        catch { #expect(error is ImageCachePipelineError) }
        await first.release()
        await second.release()
        #expect(await gate.snapshot().used == 0)
    }

    @Test func imageReturnsWhileDiskWriterIsBlocked() async throws {
        let resources = ImagePipelineResources()
        let disk = ImageCacheDiskStore(folderName: "Phase2Persist-\(UUID())", resources: resources)
        let coordinator = ImageLoadCoordinator(memory: ImageCacheMemoryStore(), disk: disk, resources: resources)
        let write = try await resources.io.acquire(kind: .write)
        let reservation = try await resources.writeBytes.acquire(1)
        let request = ImageRequest(path: "image", work: .load(maxBytes: 1))
        let value = try await coordinator.value(for: request, priority: .visible, storePolicy: .memoryAndDisk) { _ in
            ImageLoadValue(image: Self.image(), downloadedData: Data([7]), release: { await reservation.release() })
        }
        #expect(value.image != nil)
        #expect(value.payload == nil)
        #expect(await resources.writeBytes.snapshot().used == 1)
        await write.release()
        await coordinator.flushPendingWrites()
        #expect(await disk.read(forKey: request.cacheKey) == Data([7]))
        #expect(await resources.writeBytes.snapshot().used == 0)
        await coordinator.removeAll()
    }

    @Test func largeRequestUsesFileAndCleansUpAfterPersistence() async throws {
        let resources = ImagePipelineResources(limits: ImagePipelineLimits(decodeBytes: 1, writeBytes: 1))
        let disk = ImageCacheDiskStore(folderName: "Phase2File-\(UUID())", resources: resources)
        let data = try #require(Self.image().pngData())
        let location = FileLocationSpy()
        let pipeline = ImageCachePipeline(fetcher: { _, _ in
            Issue.record("대용량 요청에서 Data fetcher를 사용했습니다.")
            throw URLError(.unknown)
        }, fileFetcher: { _, _, url in
            await location.set(url)
            try data.write(to: url)
        }, disk: disk, resources: resources)
        let image = try await pipeline.loadImage(path: "large", maxBytes: data.count)
        #expect(image.size.width == 2)
        await pipeline.flushPendingWrites()
        try await waitUntil { await resources.files.snapshot().used == 0 }
        let url = try #require(await location.url)
        // Task 종료 뒤 마지막 payload 참조까지 해제되는 시점을 기다린다.
        try await waitUntil { !FileManager.default.fileExists(atPath: url.path) }
        #expect(await disk.read(forKey: "imageCache|large") == data)
        #expect(await resources.decodeBytes.snapshot().used == 0)
        #expect(await resources.network.snapshot().active == 0)
        await pipeline.removeAllCachedImages()
    }

    @Test func fetchFailureReturnsEveryReservation() async throws {
        let resources = ImagePipelineResources()
        let processor = ImagePipelineProcessor(resources: resources, fetcher: { _, _ in
            throw URLError(.notConnectedToInternet)
        }, fileFetcher: nil, decoder: { UIImage(data: $0) }, fileDecoder: { UIImage(contentsOfFile: $0.path) })
        do { _ = try await processor.download(path: "failure", maxBytes: 100); Issue.record("실패가 누락되었습니다.") }
        catch { #expect(error is URLError) }
        #expect(await resources.network.snapshot().used == 0)
        #expect(await resources.decodeBytes.snapshot().used == 0)
        #expect(await resources.writeBytes.snapshot().used == 0)
    }

    @Test func fullWriteBudgetStopsDownloadBeforeNetworkAdmission() async throws {
        let resources = ImagePipelineResources(limits: ImagePipelineLimits(writeBytes: 100))
        let held = try await resources.writeBytes.acquire(100)
        let processor = ImagePipelineProcessor(resources: resources, fetcher: { _, _ in
            Issue.record("저장 예약이 가득 찬 동안 다운로드가 시작됐습니다.")
            throw URLError(.unknown)
        }, fileFetcher: nil, decoder: { UIImage(data: $0) }, fileDecoder: { UIImage(contentsOfFile: $0.path) })
        let task = Task { try await processor.download(path: "waiting", maxBytes: 100) }
        try await waitUntil { await resources.writeBytes.snapshot().waiting == 1 }
        #expect(await resources.network.snapshot().active == 0)
        #expect(await resources.decodeBytes.snapshot().used == 0)
        task.cancel()
        do { _ = try await task.value; Issue.record("취소가 누락되었습니다.") }
        catch { #expect(error is CancellationError) }
        await held.release()
        #expect(await resources.writeBytes.snapshot().used == 0)
        #expect(await resources.writeBytes.snapshot().waiting == 0)
    }

    @Test func decodeCancellationReleasesNetworkAndBothByteReservations() async throws {
        let resources = ImagePipelineResources(limits: ImagePipelineLimits(decodes: 1))
        let held = try await resources.decode.acquire()
        let data = try #require(Self.image().pngData())
        let processor = ImagePipelineProcessor(resources: resources, fetcher: { _, _ in data },
            fileFetcher: nil, decoder: { UIImage(data: $0) }, fileDecoder: { UIImage(contentsOfFile: $0.path) })
        let task = Task { try await processor.download(path: "decode", maxBytes: data.count) }
        try await waitUntil { await resources.decode.snapshot().waiting == 1 }
        #expect(await resources.network.snapshot().active == 0)
        #expect(await resources.decodeBytes.snapshot().used == data.count)
        task.cancel()
        do { _ = try await task.value; Issue.record("취소가 누락되었습니다.") }
        catch { #expect(error is CancellationError) }
        await held.release()
        #expect(await resources.decodeBytes.snapshot().used == 0)
        #expect(await resources.writeBytes.snapshot().used == 0)
        #expect(await resources.decode.snapshot().waiting == 0)
    }

    private func waitUntil(_ predicate: () async -> Bool) async throws {
        for _ in 0..<10_000 {
            if await predicate() { return }
            await Task.yield()
        }
        Issue.record("예상한 비동기 상태에 도달하지 못했습니다.")
        throw URLError(.timedOut)
    }

    private static func image() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 2, height: 1), format: format).image { _ in }
    }
}

private actor FileLocationSpy {
    private(set) var url: URL?
    func set(_ url: URL) { self.url = url }
}
