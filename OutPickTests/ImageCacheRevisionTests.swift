import Foundation
import Testing
import UIKit
@testable import OutPick

struct ImageCacheRevisionTests {
    @Test func staleWriteCannotRestoreRemovedEntry() async {
        let disk = makeDisk()
        await disk.write(data: Data([1]), forKey: "key")
        let revision = ImageCacheRevisionClock.next()
        await disk.remove(forKey: "key", revision: revision)
        await disk.write(data: Data([1]), forKey: "key", revision: 0)
        #expect(await disk.read(forKey: "key", revision: revision) == nil)
        await disk.write(data: Data([2]), forKey: "key", revision: revision)
        #expect(await disk.read(forKey: "key", revision: revision) == Data([2]))
        await disk.removeAll(revision: ImageCacheRevisionClock.next())
    }

    @Test func delayedClearKeepsNewGenerationButRejectsOldWrites() async {
        let disk = makeDisk()
        await disk.write(data: Data([1]), forKey: "old")
        let clearRevision = ImageCacheRevisionClock.next()
        let storeRevision = ImageCacheRevisionClock.next()
        await disk.write(data: Data([2]), forKey: "new", revision: storeRevision)
        // clear 이후 시작한 load의 쓰기가 clear 명령보다 먼저 도착하는 경우다.
        await disk.write(data: Data([3]), forKey: "sameGeneration", revision: clearRevision)
        await disk.removeAll(revision: clearRevision)
        await disk.write(data: Data([1]), forKey: "old", revision: 0)
        #expect(await disk.read(forKey: "old", revision: clearRevision) == nil)
        #expect(await disk.read(forKey: "new", revision: storeRevision) == Data([2]))
        #expect(await disk.read(forKey: "sameGeneration", revision: clearRevision) == Data([3]))
        await disk.removeAll(revision: ImageCacheRevisionClock.next())
    }

    @Test func delayedRemoveDoesNotDeleteNewWriteOfSameGeneration() async {
        let disk = makeDisk()
        let revision = ImageCacheRevisionClock.next()
        await disk.write(data: Data([2]), forKey: "key", revision: revision)
        await disk.remove(forKey: "key", revision: revision)
        #expect(await disk.read(forKey: "key", revision: revision) == Data([2]))
        await disk.removeAll(revision: ImageCacheRevisionClock.next())
    }

    @Test func concurrentDiskHitsDecodeOnceAndNeverFetch() async throws {
        let disk = makeDisk()
        let counter = ImageDecodeCounter()
        let image = makeImage(width: 2)
        let data = try #require(image.pngData())
        // 이전 버전의 cache key와 파일을 그대로 읽어야 한다.
        await disk.write(data: data, forKey: "imageCache|legacy")
        let pipeline = ImageCachePipeline(fetcher: { _, _ in
            Issue.record("disk hit에서 네트워크를 요청하면 안 됩니다.")
            throw URLError(.unknown)
        }, disk: disk, decoder: { data in counter.decode(data) })
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    let result = try await pipeline.loadImage(path: "legacy", maxBytes: 100)
                    #expect(result.size.width == 2)
                }
            }
            try await group.waitForAll()
        }
        #expect(counter.count == 1)
        await pipeline.removeAllCachedImages()
    }

    @Test func cacheOnlyDoesNotFetchAndStoreRemoveRemainUsable() async throws {
        let disk = makeDisk()
        let pipeline = ImageCachePipeline(fetcher: { _, _ in
            Issue.record("cache-only는 네트워크를 시작하면 안 됩니다.")
            throw URLError(.unknown)
        }, disk: disk)
        #expect(await pipeline.cachedImage(path: "image") == nil)
        let image = makeImage(width: 3)
        try await pipeline.storeImageData(try #require(image.pngData()), path: "image")
        #expect(await pipeline.cachedImage(path: "image")?.size.width == 3)
        await pipeline.removeImage(path: "image")
        #expect(await pipeline.cachedImage(path: "image") == nil)
        await pipeline.removeAllCachedImages()
    }

    private func makeDisk() -> ImageCacheDiskStore {
        ImageCacheDiskStore(folderName: "ImageRevisionTests-\(UUID())")
    }

    private func makeImage(width: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: 1), format: format).image { _ in }
    }
}

private final class ImageDecodeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCount
    }
    func decode(_ data: Data) -> UIImage? {
        lock.lock()
        storedCount += 1
        lock.unlock()
        return UIImage(data: data)
    }
}
