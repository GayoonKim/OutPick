import XCTest
import UIKit
@testable import OutPick

@MainActor
final class ImageDirectDiskDecodingTests: XCTestCase {
    func testUnlimitedDiskPathBypassesOccupiedDecodeAndIOGates() async throws {
        let resources = ImagePipelineResources(limits: ImagePipelineLimits(decodes: 1, diskOperations: 1))
        let disk = ImageCacheDiskStore(folderName: "UnlimitedDecode-\(UUID())", resources: resources)
        await disk.write(data: Data([1]), forKey: "imageCache|hit")
        let decodeLease = try await resources.decode.acquire()
        let ioLease = try await resources.io.acquire(kind: .read)
        let decoded = expectation(description: "기존 decode/IO 게이트 점유 중에도 디코딩")
        let pipeline = ImageCachePipeline(fetcher: { _, _ in XCTFail("다운로드 금지"); return Data() },
            disk: disk, resources: resources, usesDirectDiskFileDecoding: true, bypassDirectDiskLimits: true,
            fileDecoder: { _ in decoded.fulfill(); return UIImage() })
        let task = Task { await pipeline.cachedImage(path: "hit") }
        await fulfillment(of: [decoded], timeout: 3)
        await decodeLease.release()
        await ioLease.release()
        let image = await task.value
        XCTAssertNotNil(image)
        await pipeline.removeAllCachedImages()
    }

    func testPreparationUsesDiskOnlyAndAdmitsImageToMemory() async throws {
        let disk = ImageCacheDiskStore(folderName: "Preparation-\(UUID())")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { _ in }
        await disk.write(data: try XCTUnwrap(image.pngData()), forKey: "imageCache|hit")
        let pipeline = ImageCachePipeline(fetcher: { _, _ in XCTFail("먼 구간 준비는 다운로드 금지"); return Data() },
            memory: ImageCacheMemoryStore(totalCostLimitBytes: 16 * 1024 * 1024, usesLRU: true), disk: disk,
            usesDirectDiskFileDecoding: true)
        await pipeline.prepareDiskImage(path: "miss")
        XCTAssertNil(pipeline.cachedMemoryImageImmediately(path: "miss"))
        await pipeline.prepareDiskImage(path: "hit")
        XCTAssertNotNil(pipeline.cachedMemoryImageImmediately(path: "hit"))
        await pipeline.removeAllCachedImages()
    }

    func testLeasePreservesOldBytesAcrossReplacementAndDeletionThenUnlinks() async throws {
        let disk = ImageCacheDiskStore(folderName: "ReadLease-\(UUID())")
        await disk.write(data: Data([1]), forKey: "key")
        var lease = try await disk.readLease(forKey: "key", revision: 0)
        let url = try XCTUnwrap(lease?.url)
        await disk.write(data: Data([2]), forKey: "key")
        XCTAssertEqual(try Data(contentsOf: url), Data([1]))
        let current = await disk.read(forKey: "key")
        XCTAssertEqual(current, Data([2]))
        await disk.removeAll(revision: ImageCacheRevisionClock.next())
        XCTAssertEqual(try Data(contentsOf: url), Data([1]))
        lease = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testDirectDiskHitDoesNotNeedCompressedByteOrDownloadFileSlots() async throws {
        let resources = ImagePipelineResources(limits: ImagePipelineLimits(downloads: 1, decodeBytes: 1, writeBytes: 1))
        let disk = ImageCacheDiskStore(folderName: "DirectDecode-\(UUID())", resources: resources)
        await disk.write(data: Data([1, 2, 3]), forKey: "imageCache|image")
        let bytes = try await resources.decodeBytes.acquire(1)
        let files = try await resources.files.acquire()
        let decoded = expectation(description: "Data/전송파일 예산이 차도 캐시 파일 디코딩")
        let pipeline = ImageCachePipeline(fetcher: { _, _ in XCTFail("캐시 hit에서 다운로드 금지"); return Data() },
            disk: disk, resources: resources, usesDirectDiskFileDecoding: true,
            decoder: { _ in XCTFail("Data 경로 사용 금지"); return nil },
            fileDecoder: { url in
                XCTAssertEqual(try? Data(contentsOf: url), Data([1, 2, 3]))
                decoded.fulfill()
                return UIImage()
            })
        let task = Task { try await pipeline.loadImage(path: "image", maxBytes: 100) }
        await fulfillment(of: [decoded], timeout: 3)
        await bytes.release()
        await files.release()
        _ = try await task.value
        await pipeline.removeAllCachedImages()
        let state = await resources.decode.snapshot()
        XCTAssertEqual(state.used, 0)
    }

    func testFileDecodeFailureFallsBackToExistingDataDecoder() async throws {
        let disk = ImageCacheDiskStore(folderName: "DirectFallback-\(UUID())")
        await disk.write(data: Data([1]), forKey: "imageCache|image")
        let fallback = expectation(description: "기존 디코딩 복구")
        let pipeline = ImageCachePipeline(fetcher: { _, _ in XCTFail("복구 가능한 캐시는 다운로드 금지"); return Data() },
            disk: disk, usesDirectDiskFileDecoding: true,
            decoder: { _ in fallback.fulfill(); return UIImage() }, fileDecoder: { _ in nil })
        _ = try await pipeline.loadImage(path: "image", maxBytes: 100)
        await fulfillment(of: [fallback], timeout: 3)
        await pipeline.removeAllCachedImages()
    }
}
