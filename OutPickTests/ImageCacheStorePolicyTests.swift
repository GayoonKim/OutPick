import Foundation
import Testing
import UIKit
@testable import OutPick

struct ImageCacheStorePolicyTests {
    @Test(arguments: [false, true]) func transientFileTransportRemovesTemporaryFile(fails: Bool) async throws {
        let resources = ImagePipelineResources(limits: ImagePipelineLimits(decodeBytes: 1, writeBytes: 1))
        let disk = diskStore(resources: resources)
        let location = PolicyFileLocation()
        let bytes = try #require(image(width: 3).pngData())
        let pipeline = ImageCachePipeline(fetcher: { _, _ in
            Issue.record("큰 원본 요청은 파일 전송을 사용해야 합니다.")
            throw URLError(.unknown)
        }, fileFetcher: { _, _, url in
            await location.set(url)
            try bytes.write(to: url)
            if fails { throw URLError(.networkConnectionLost) }
        }, disk: disk, resources: resources)
        do {
            let value = try await pipeline.loadImage(path: "file-original", maxBytes: bytes.count, storePolicy: .transient, priority: .visible)
            #expect(!fails)
            #expect(value.size.width == 3)
        } catch {
            #expect(fails)
            #expect((error as? URLError)?.code == .networkConnectionLost)
        }
        let url = try #require(await location.url)
        let deadline = Date().addingTimeInterval(3)
        while FileManager.default.fileExists(atPath: url.path), Date() < deadline { await Task.yield() }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(await resources.files.snapshot().used == 0)
        #expect(await disk.read(forKey: "imageCache|file-original") == nil)
        #expect(await pipeline.cachedImage(path: "file-original") == nil)
        await pipeline.removeAllCachedImages()
    }

    @Test func memoryOnlyDownloadCanLaterPersistWithoutAnotherFetch() async throws {
        let calls = PolicySignal()
        let data = try #require(image(width: 3).pngData())
        let disk = diskStore()
        let pipeline = ImageCachePipeline(fetcher: { _, _ in
            await calls.increment()
            return data
        }, disk: disk, promotionEncoding: ImageCachePromotionEncoding(maximumBytes: 4096, encode: { $0.pngData() }))
        let first = try await pipeline.loadImage(path: "comment", maxBytes: 4096, storePolicy: .memoryOnly, priority: .visible)
        await pipeline.flushPendingWrites()
        #expect(await disk.read(forKey: "imageCache|comment") == nil)
        let next = try await pipeline.loadImage(path: "comment", maxBytes: 4096, storePolicy: .memoryAndDisk, priority: .visible)
        #expect(first === next)
        await pipeline.flushPendingWrites()
        #expect(await disk.read(forKey: "imageCache|comment") != nil)
        #expect(await calls.count == 1)
        await pipeline.removeAllCachedImages()
    }

    @Test func memoryOnlyCanReadExistingDiskWithoutReencoding() async throws {
        let disk = diskStore()
        let data = try #require(image(width: 3).pngData())
        await disk.write(data: data, forKey: "imageCache|existing")
        let pipeline = ImageCachePipeline(fetcher: { _, _ in
            Issue.record("디스크 hit를 다시 다운로드하면 안 됩니다.")
            throw URLError(.unknown)
        }, disk: disk, promotionEncoding: ImageCachePromotionEncoding(maximumBytes: 4096, encode: { _ in
            Issue.record("이미 디스크에 있는 이미지를 재인코딩하면 안 됩니다.")
            return nil
        }))
        #expect(try await pipeline.loadImage(path: "existing", maxBytes: 4096, storePolicy: .memoryOnly, priority: .visible).size.width == 3)
        await pipeline.flushPendingWrites()
        #expect(await disk.read(forKey: "imageCache|existing") == data)
        await pipeline.removeAllCachedImages()
    }

    @Test func transientCancellationReleasesTransportAndEveryReservation() async throws {
        let started = PolicySignal()
        let finished = PolicySignal()
        let resources = ImagePipelineResources()
        let disk = diskStore(resources: resources)
        let pipeline = ImageCachePipeline(fetcher: { _, _ in
            await started.increment()
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return Data()
        }, disk: disk, resources: resources)
        let request = Task {
            defer { Task { await finished.increment() } }
            return try await pipeline.loadImage(path: "cancelled-original", maxBytes: 4096, storePolicy: .transient, priority: .visible)
        }
        await started.wait(for: 1)
        request.cancel()
        do { _ = try await request.value; Issue.record("취소된 원본 요청이 성공했습니다.") }
        catch { #expect(error is CancellationError) }
        await finished.wait(for: 1)
        let deadline = Date().addingTimeInterval(3)
        while await resources.writeBytes.snapshot().used != 0, Date() < deadline { await Task.yield() }
        #expect(await resources.writeBytes.snapshot().used == 0)
        #expect(await resources.decodeBytes.snapshot().used == 0)
        #expect(await resources.network.snapshot().used == 0)
        #expect(await disk.read(forKey: "imageCache|cancelled-original") == nil)
        await pipeline.removeAllCachedImages()
    }

    @Test func transientIgnoresExistingCachesAndDoesNotReplaceThem() async throws {
        let memory = ImageCacheMemoryStore()
        let disk = diskStore()
        let calls = PolicySignal()
        let cached = image(width: 2)
        let freshData = try #require(image(width: 4).pngData())
        memory.set(cached, forKey: "imageCache|avatar")
        let cachedData = try #require(cached.pngData())
        await disk.write(data: cachedData, forKey: "imageCache|avatar")
        let pipeline = ImageCachePipeline(fetcher: { _, _ in
            await calls.increment()
            return freshData
        }, memory: memory, disk: disk)
        for _ in 0..<2 {
            let result = try await pipeline.loadImage(path: "avatar", maxBytes: 4096, storePolicy: .transient, priority: .visible)
            #expect(result.size.width == 4)
        }
        #expect(await calls.count == 2)
        #expect(memory.image(forKey: "imageCache|avatar") === cached)
        #expect(await disk.read(forKey: "imageCache|avatar") == cachedData)
        await pipeline.removeAllCachedImages()
    }

    @Test func simultaneousTransientConsumersShareWorkButDoNotCacheResult() async throws {
        let gate = PolicyGate()
        let demand = PolicySignal()
        let starts = PolicySignal()
        let memory = ImageCacheMemoryStore()
        let disk = diskStore()
        let coordinator = ImageLoadCoordinator(memory: memory, disk: disk, onDemandChange: { request, _, count in
            if request.isTransient { Task { await demand.reach(count) } }
        })
        let request = ImageRequest(path: "original", work: .transient(maxBytes: 4096))
        let result = image(width: 5)
        let data = try #require(result.pngData())
        let tasks = (0..<10).map { _ in
            Task {
                try await coordinator.value(for: request, priority: .visible, storePolicy: .transient) { _ in
                    await starts.increment()
                    await gate.wait()
                    return ImageLoadValue(image: result, downloadedData: data)
                }
            }
        }
        await demand.wait(for: 10)
        await gate.open()
        for task in tasks { #expect(try await task.value.image === result) }
        await coordinator.flushPendingWrites()
        #expect(await starts.count == 1)
        #expect(memory.image(forKey: request.cacheKey) == nil)
        #expect(await disk.read(forKey: request.cacheKey) == nil)
        await coordinator.removeAll()
    }

    @Test func transientAndPersistentRequestsForSamePathStaySeparate() async throws {
        let gate = PolicyGate()
        let starts = PolicySignal()
        let memory = ImageCacheMemoryStore()
        let disk = diskStore()
        let coordinator = ImageLoadCoordinator(memory: memory, disk: disk)
        let original = image(width: 6)
        let thumbnail = image(width: 2)
        let transient = Task {
            try await coordinator.value(for: ImageRequest(path: "same", work: .transient(maxBytes: 100)), priority: .visible, storePolicy: .transient) { _ in
                await starts.increment()
                await gate.wait()
                return ImageLoadValue(image: original)
            }
        }
        let persistent = Task {
            try await coordinator.value(for: ImageRequest(path: "same", work: .load(maxBytes: 100)), priority: .visible, storePolicy: .memoryOnly) { _ in
                await starts.increment()
                await gate.wait()
                return ImageLoadValue(image: thumbnail)
            }
        }
        await starts.wait(for: 2)
        await gate.open()
        #expect(try await transient.value.image === original)
        #expect(try await persistent.value.image === thumbnail)
        #expect(memory.image(forKey: "imageCache|same") === thumbnail)
        await coordinator.removeAll()
    }

    @Test func memoryHitReturnsBeforeEncodingAndPromotesOnlyOnce() async throws {
        let gate = PolicyGate()
        let started = PolicySignal()
        let memory = ImageCacheMemoryStore()
        let disk = diskStore()
        let expected = image(width: 3)
        let bytes = try #require(expected.pngData())
        memory.set(expected, forKey: "imageCache|promote")
        let coordinator = ImageLoadCoordinator(memory: memory, disk: disk, promotion: { image in
            await started.increment()
            await gate.wait()
            return ImageLoadValue(image: image, downloadedData: bytes)
        })
        #expect(await coordinator.cachedMemoryImage(path: "promote", promote: false) === expected)
        #expect(await started.count == 0)
        #expect(await coordinator.cachedMemoryImage(path: "promote", promote: true) === expected)
        await started.wait(for: 1)
        for _ in 0..<20 { #expect(await coordinator.cachedMemoryImage(path: "promote", promote: true) === expected) }
        #expect(await disk.read(forKey: "imageCache|promote") == nil)
        await gate.open()
        await coordinator.flushPendingWrites()
        #expect(await started.count == 1)
        #expect(await disk.read(forKey: "imageCache|promote") == bytes)
        _ = await coordinator.cachedMemoryImage(path: "promote", promote: true)
        await coordinator.flushPendingWrites()
        #expect(await started.count == 1)
        await coordinator.removeAll()
    }

    @Test(arguments: [false, true]) func invalidationRejectsLatePromotionAndReleasesPayload(clearAll: Bool) async throws {
        let gate = PolicyGate()
        let started = PolicySignal()
        let released = PolicySignal()
        let memory = ImageCacheMemoryStore()
        let disk = diskStore()
        memory.set(image(width: 3), forKey: "imageCache|old")
        let coordinator = ImageLoadCoordinator(memory: memory, disk: disk, promotion: { image in
            await started.increment()
            await gate.wait() // 취소를 무시하는 느린 변환을 재현한다.
            return ImageLoadValue(image: image, downloadedData: Data([1]), release: { await released.increment() })
        })
        _ = await coordinator.cachedMemoryImage(path: "old", promote: true)
        await started.wait(for: 1)
        if clearAll { await coordinator.removeAll() } else { await coordinator.remove(path: "old") }
        await gate.open()
        await released.wait(for: 1)
        #expect(memory.image(forKey: "imageCache|old") == nil)
        // 삭제 세대는 coordinator가 전달하는 값으로 확인한다.
        _ = try await coordinator.value(for: ImageRequest(path: "old", work: .cache), priority: .visible, storePolicy: .memoryOnly) { revision in
            #expect(await disk.read(forKey: "imageCache|old", revision: revision) == nil)
            return ImageLoadValue(image: nil)
        }
        await coordinator.removeAll()
    }

    @Test func failedPromotionCanRetryWithoutDiscardingDisplayedImage() async throws {
        let calls = PolicySignal()
        let memory = ImageCacheMemoryStore()
        let disk = diskStore()
        let expected = image(width: 3)
        let bytes = try #require(expected.pngData())
        memory.set(expected, forKey: "imageCache|retry")
        let coordinator = ImageLoadCoordinator(memory: memory, disk: disk, promotion: { image in
            let count = await calls.increment()
            if count == 1 { throw URLError(.cannotDecodeContentData) }
            return ImageLoadValue(image: image, downloadedData: bytes)
        })
        _ = await coordinator.cachedMemoryImage(path: "retry", promote: true)
        await coordinator.flushPendingWrites()
        #expect(memory.image(forKey: "imageCache|retry") === expected)
        #expect(await disk.read(forKey: "imageCache|retry") == nil)
        _ = await coordinator.cachedMemoryImage(path: "retry", promote: true)
        await coordinator.flushPendingWrites()
        #expect(await calls.count == 2)
        #expect(await disk.read(forKey: "imageCache|retry") == bytes)
        await coordinator.removeAll()
    }

    @Test func pipelinePromotionUsesSharedPreparationAndWriteBudgets() async throws {
        let memory = ImageCacheMemoryStore()
        let resources = ImagePipelineResources()
        let disk = diskStore(resources: resources)
        let expected = image(width: 3)
        memory.set(expected, forKey: "imageCache|encoded")
        let blocker = try await resources.decode.acquire(resources.limits.decodes)
        let pipeline = ImageCachePipeline(fetcher: { _, _ in
            Issue.record("메모리 hit 승격에서 다운로드하면 안 됩니다.")
            throw URLError(.unknown)
        }, memory: memory, disk: disk, resources: resources,
        promotionEncoding: ImageCachePromotionEncoding(maximumBytes: 4096, encode: { $0.pngData() }))
        #expect(try await pipeline.loadImage(path: "encoded", maxBytes: 4096) === expected)
        #expect(await disk.read(forKey: "imageCache|encoded") == nil)
        await blocker.release()
        await pipeline.flushPendingWrites()
        let bytes = try #require(await disk.read(forKey: "imageCache|encoded"))
        #expect(UIImage(data: bytes)?.size.width == 3)
        #expect(await resources.writeBytes.snapshot().used == 0)
        #expect(await resources.decode.snapshot().used == 0)
        await pipeline.removeAllCachedImages()
    }

    @Test func oversizedEncodingDoesNotPersistAndReturnsBudget() async throws {
        let memory = ImageCacheMemoryStore()
        let resources = ImagePipelineResources()
        let disk = diskStore(resources: resources)
        let expected = image(width: 3)
        memory.set(expected, forKey: "imageCache|oversized")
        let pipeline = ImageCachePipeline(fetcher: { _, _ in throw URLError(.unknown) },
            memory: memory, disk: disk, resources: resources,
            promotionEncoding: ImageCachePromotionEncoding(maximumBytes: 8, encode: { _ in Data(repeating: 1, count: 9) }))
        #expect(try await pipeline.loadImage(path: "oversized", maxBytes: 10) === expected)
        await pipeline.flushPendingWrites()
        #expect(await disk.read(forKey: "imageCache|oversized") == nil)
        #expect(await resources.writeBytes.snapshot().used == 0)
        #expect(memory.image(forKey: "imageCache|oversized") === expected)
        await pipeline.removeAllCachedImages()
    }

    private func diskStore(resources: ImagePipelineResources = .shared) -> ImageCacheDiskStore {
        ImageCacheDiskStore(folderName: "ImagePolicyTests-\(UUID())", resources: resources)
    }

    private func image(width: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: 2), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: 2))
        }
    }
}

private actor PolicyGate {
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

private actor PolicyFileLocation {
    private(set) var url: URL?
    func set(_ url: URL) { self.url = url }
}

private actor PolicySignal {
    private(set) var count = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    @discardableResult func increment() -> Int { reach(count + 1); return count }
    func reach(_ value: Int) {
        count = max(count, value)
        let ready = waiters.filter { $0.0 <= count }
        waiters.removeAll { $0.0 <= count }
        ready.forEach { $0.1.resume() }
    }
    func wait(for value: Int) async {
        if count >= value { return }
        await withCheckedContinuation { waiters.append((value, $0)) }
    }
}
