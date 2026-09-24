import XCTest
import UIKit
import CryptoKit
@testable import OutPick

@MainActor
final class ImageLRUMemoryStoreTests: XCTestCase {
    func testPreparationNeverEvictsExistingImagesAndStopsOnPressure() throws {
        let photo = image()
        let cg = try XCTUnwrap(photo.cgImage)
        let cost = cg.bytesPerRow * cg.height
        let store = ImageLRUMemoryStore(maximumBytes: cost, observesPressure: false)
        store.set(photo, forKey: "near")
        store.setIfRoom(photo, forKey: "far")
        XCTAssertNotNil(store.image(forKey: "near"))
        XCTAssertNil(store.image(forKey: "far"))
        store.removeAll()
        store.setIfRoom(photo, forKey: "far")
        XCTAssertNotNil(store.image(forKey: "far"))
        store.handlePressure(.warning)
        store.setIfRoom(photo, forKey: "new")
        XCTAssertNil(store.image(forKey: "new"))
        XCTAssertFalse(store.canPrepareDiskImage)
    }

    func testDiskReadProtectsRecentlyUsedFileFromCapacityTrim() async throws {
        let folder = "DiskLRU-\(UUID())"
        let disk = ImageCacheDiskStore(folderName: folder, maxSizeBytes: 8, trimTargetBytes: 6)
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent(folder)
        defer { try? FileManager.default.removeItem(at: base) }
        let data = Data([1, 2, 3])
        await disk.write(data: data, forKey: "A")
        await disk.write(data: data, forKey: "B")
        for (key, time) in [("A", 1.0), ("B", 2.0)] {
            let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".bin"
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: time)], ofItemAtPath: base.appendingPathComponent(name).path)
        }
        _ = await disk.read(forKey: "A")
        await disk.write(data: data, forKey: "C")
        let a = await disk.read(forKey: "A"), b = await disk.read(forKey: "B"), c = await disk.read(forKey: "C")
        XCTAssertEqual(a, data)
        XCTAssertNil(b)
        XCTAssertEqual(c, data)
    }

    private func image() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { _ in }
    }

    func testReadUpdatesRecencyAndOldestEntryIsEvicted() throws {
        let photo = image()
        let cg = try XCTUnwrap(photo.cgImage)
        let cost = cg.bytesPerRow * cg.height
        let store = ImageLRUMemoryStore(maximumBytes: cost * 2, observesPressure: false)
        store.set(photo, forKey: "A")
        store.set(photo, forKey: "B")
        XCTAssertTrue(store.image(forKey: "A") === photo)
        store.set(photo, forKey: "C")
        XCTAssertNil(store.image(forKey: "B"))
        XCTAssertNotNil(store.image(forKey: "A"))
        XCTAssertNotNil(store.image(forKey: "C"))
        XCTAssertEqual(store.snapshot().bytes, cost * 2)
        store.set(photo, forKey: "A")
        XCTAssertEqual(store.snapshot().bytes, cost * 2)
        store.remove(forKey: "A")
        XCTAssertEqual(store.snapshot().bytes, cost)
        store.removeAll()
        XCTAssertEqual(store.snapshot().bytes, 0)
    }

    func testPressureClearsCacheLimitsRefillAndNormalRestoresBudget() throws {
        let photo = image()
        let cg = try XCTUnwrap(photo.cgImage)
        let cost = cg.bytesPerRow * cg.height
        let store = ImageLRUMemoryStore(maximumBytes: cost * 4, observesPressure: false)
        store.set(photo, forKey: "A")
        store.handlePressure(.warning)
        XCTAssertEqual(store.snapshot().count, 0)
        XCTAssertEqual(store.snapshot().limit, cost)
        store.set(photo, forKey: "B")
        store.set(photo, forKey: "C")
        XCTAssertNil(store.image(forKey: "B"))
        store.handlePressure(.critical)
        store.handlePressure(.warning)
        store.set(photo, forKey: "D")
        XCTAssertEqual(store.snapshot().count, 0)
        store.handlePressure(.normal)
        XCTAssertEqual(store.snapshot().limit, cost * 4)
        store.set(photo, forKey: "E")
        XCTAssertNotNil(store.image(forKey: "E"))
    }

    func testOversizeImageIsReturnedToCallerButNotRetainedByCache() {
        let photo = image()
        let store = ImageLRUMemoryStore(maximumBytes: 1, observesPressure: false)
        store.set(photo, forKey: "large")
        XCTAssertNil(store.image(forKey: "large"))
        XCTAssertEqual(store.snapshot().bytes, 0)
    }

    func testWrapperUsesLRUWithoutRetainingEvictedImagesInNSCache() throws {
        let photo = image()
        let cg = try XCTUnwrap(photo.cgImage)
        let store = ImageCacheMemoryStore(totalCostLimitBytes: cg.bytesPerRow * cg.height, usesLRU: true)
        store.set(photo, forKey: "A")
        store.set(photo, forKey: "B")
        XCTAssertNil(store.image(forKey: "A"))
        XCTAssertNotNil(store.image(forKey: "B"))
        store.removeAll()
        XCTAssertNil(store.image(forKey: "B"))
    }
}
