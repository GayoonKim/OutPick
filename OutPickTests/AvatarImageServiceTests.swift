import Foundation
import Testing
import UIKit
import FirebaseStorage
@testable import OutPick

struct AvatarImageServiceTests {
    @Test @MainActor func continuousAvatarViewsPromoteMemoryThenReuseDiskWithoutAnotherFetch() async throws {
        let fixture = try AvatarServiceFixture()
        let commentManager = fixture.service.scoped { .memoryOnly }
        let roomManager = fixture.service.scoped { .memoryAndDisk }
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func show(_ manager: AvatarImageManaging) async throws -> AvatarImageView {
            let view = AvatarImageView(frame: CGRect(x: 10, y: 100, width: 60, height: 60))
            controller.view.addSubview(view)
            view.configure(userID: "qa", path: "continuous-thumb", manager: manager)
            for _ in 0..<200 where view.presentation.status != .loaded {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            #expect(view.presentation.status == .loaded)
            return view
        }
        do {
            let comment = try await show(commentManager)
            await fixture.pipeline.flushPendingWrites()
            #expect(await fixture.disk.read(forKey: "imageCache|continuous-thumb") == nil)
            let firstImage = try #require(comment.presentation.image)
            comment.removeFromSuperview()
            let room = try await show(roomManager)
            #expect(room.presentation.image === firstImage)
            await fixture.pipeline.flushPendingWrites()
            let saved = try #require(await fixture.disk.read(forKey: "imageCache|continuous-thumb"))
            #expect(await fixture.calls.limits.count == 1)
            print("[AvatarCrossScreenQA] memoryToDisk fetches=1 diskPresent=true sameImage=true")
            room.removeFromSuperview()
            // 같은 앱 세션에서 메모리만 비워 디스크 재사용을 메모리 적중과 구분한다.
            fixture.memory.removeAll()
            #expect(commentManager.cachedAvatarImmediately(for: "continuous-thumb") == nil)
            let diskComment = try await show(commentManager)
            #expect(diskComment.presentation.image != nil)
            await fixture.pipeline.flushPendingWrites()
            #expect(await fixture.disk.read(forKey: "imageCache|continuous-thumb") == saved)
            #expect(await fixture.calls.limits.count == 1)
            print("[AvatarCrossScreenQA] diskToComment fetches=1 bytesUnchanged=true processRestart=false")
            diskComment.removeFromSuperview()
            await fixture.cleanup()
        } catch {
            await fixture.cleanup()
            throw error
        }
    }

    @Test func originalTimeoutAllowsImmediateRetryAndRejectsLateTransport() async throws {
        let timer = AsyncStream<Void>.makeStream()
        let gate = AvatarTestGate()
        let fetches = AvatarFetchRecorder()
        let fixture = try AvatarServiceFixture(originalTimeoutWait: {
            for await _ in timer.stream { return }
            try Task.checkCancellation()
        }, beforeFetch: {
            await fetches.record(1)
            if await fetches.limits.count == 1 { await gate.wait() }
        })
        let first = Task { try await fixture.service.loadOriginalAvatar(for: "original") }
        await gate.waitUntilStarted()
        timer.continuation.yield(())
        do { _ = try await first.value; Issue.record("원본 시간 초과가 성공했습니다.") }
        catch { #expect((error as? URLError)?.code == .timedOut) }
        // 재시도 자체에는 억제가 없다. 실제 전송은 기존 작업의 쓰기 permit 반환을 기다릴 수 있다.
        let retry = Task { try await fixture.service.loadOriginalAvatar(for: "original") }
        await gate.release()
        _ = try await retry.value
        #expect(await fetches.limits.count == 2)
        await fixture.pipeline.flushPendingWrites()
        #expect(await fixture.service.cachedAvatar(for: "original") == nil)
        #expect(await fixture.disk.read(forKey: "imageCache|original") == nil)
        await fixture.cleanup()
    }

    @Test func closingOriginalBeforeDeadlineRemainsCancellation() async throws {
        let timer = AsyncStream<Void>.makeStream()
        let gate = AvatarTestGate()
        let fixture = try AvatarServiceFixture(originalTimeoutWait: {
            for await _ in timer.stream { return }
            try Task.checkCancellation()
        }, beforeFetch: { await gate.wait() })
        let request = Task { try await fixture.service.loadOriginalAvatar(for: "original") }
        await gate.waitUntilStarted()
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
        await gate.release()
        await fixture.cleanup()
    }

    @Test func thumbnailDoesNotStartOriginalDeadline() async throws {
        let fixture = try AvatarServiceFixture(originalTimeoutWait: {
            Issue.record("썸네일에 원본 제한이 적용됐습니다.")
            throw URLError(.timedOut)
        })
        _ = try await fixture.service.loadAvatar(for: "thumb", maxBytes: 1)
        await fixture.cleanup()
    }
    @Test @MainActor func immediateReadSharesCacheWithoutStoringAndHonorsRemoval() async throws {
        let fixture = try AvatarServiceFixture()
        let comment = fixture.service.scoped { .memoryOnly }
        let room = fixture.service.scoped { .memoryAndDisk }
        #expect(comment.cachedAvatarImmediately(for: "thumb") == nil)
        let image = try await comment.loadAvatar(for: "thumb", maxBytes: 1)
        #expect(comment.cachedAvatarImmediately(for: "thumb") === image)
        #expect(room.cachedAvatarImmediately(for: "thumb") === image)
        await fixture.pipeline.flushPendingWrites()
        #expect(await fixture.disk.read(forKey: "imageCache|thumb") == nil)
        // 즉시 표시는 읽기만 하고 기존 비동기 경로에서 참여방 디스크 승격을 보장한다.
        _ = await room.cachedAvatar(for: "thumb")
        await fixture.pipeline.flushPendingWrites()
        #expect(await fixture.disk.read(forKey: "imageCache|thumb") != nil)
        await fixture.service.removeCachedAvatar(for: "thumb")
        #expect(room.cachedAvatarImmediately(for: "thumb") == nil)
        #expect(await fixture.calls.limits.count == 1)
        await fixture.cleanup()
    }
    @Test func unavailablePathStaysBlockedUntilExplicitRefreshOrSessionChange() async throws {
        let fixture = try AvatarServiceFixture(failure: NSError(domain: StorageErrorDomain, code: StorageErrorCode.objectNotFound.rawValue))
        for _ in 0..<3 { _ = try? await fixture.service.loadAvatar(for: "missing", maxBytes: 1) }
        #expect(await fixture.calls.limits.count == 1)
        await fixture.service.resetAvatarFailures(paths: ["missing"])
        _ = try? await fixture.service.loadAvatar(for: "missing", maxBytes: 1)
        #expect(await fixture.calls.limits.count == 2)
        await fixture.service.transitionAvatarSession(to: "next")
        _ = try? await fixture.service.loadAvatar(for: "missing", maxBytes: 1)
        #expect(await fixture.calls.limits.count == 3)
        await fixture.cleanup()
    }
    @Test(arguments: [StorageErrorCode.objectNotFound.rawValue, StorageErrorCode.unauthorized.rawValue, StorageErrorCode.unknown.rawValue])
    func storageFailureClassificationPreservesTransientErrors(code: Int) async throws {
        let fixture = try AvatarServiceFixture(failure: NSError(domain: StorageErrorDomain, code: code))
        do {
            _ = try await fixture.service.loadAvatar(for: "failed", maxBytes: 1)
            Issue.record("실패한 Storage 요청이 성공했습니다.")
        } catch {
            if code == StorageErrorCode.unknown.rawValue {
                #expect((error as NSError).code == code)
            } else {
                #expect((error as? AvatarImageLoadingError) == .unavailable)
            }
        }
        await fixture.cleanup()
    }
    @Test @MainActor func scopesShareMemoryAndPromoteWithoutDownloadingAgain() async throws {
        let fixture = try AvatarServiceFixture()
        let comment = fixture.service.scoped { .memoryOnly }
        let room = fixture.service.scoped { .memoryAndDisk }
        let first = try await comment.loadAvatar(for: "thumb", maxBytes: 1)
        await fixture.pipeline.flushPendingWrites()
        #expect(await fixture.disk.read(forKey: "imageCache|thumb") == nil)
        #expect(await room.cachedAvatar(for: "thumb") === first)
        await fixture.pipeline.flushPendingWrites()
        #expect(await fixture.disk.read(forKey: "imageCache|thumb") != nil)
        #expect(await fixture.calls.limits == [AvatarImageRequest.thumbnailMaximumBytes])
        await fixture.cleanup()
    }

    @Test func originalBypassesThumbnailCacheAndIsNeverStored() async throws {
        let fixture = try AvatarServiceFixture()
        _ = try await fixture.service.loadAvatar(for: "same", maxBytes: 1)
        _ = try await fixture.service.loadOriginalAvatar(for: "same")
        _ = try await fixture.service.loadOriginalAvatar(for: "same")
        await fixture.pipeline.flushPendingWrites()
        #expect(await fixture.calls.limits == [3 * 1024 * 1024, 20 * 1024 * 1024, 20 * 1024 * 1024])
        #expect(await fixture.disk.read(forKey: "imageCache|same") == nil)
        #expect(await fixture.service.cachedAvatar(AvatarImageRequest(path: "same", representation: .original, cachePolicy: .memoryAndDisk)) == nil)
        await fixture.cleanup()
    }

    @Test func logoutClearsDiskAndRejectsRequestsUntilNextSession() async throws {
        let fixture = try AvatarServiceFixture()
        await fixture.service.transitionAvatarSession(to: "first")
        let token = await fixture.service.avatarSessionToken()
        _ = try await fixture.service.loadAvatar(AvatarImageRequest(path: "private", representation: .thumbnail, cachePolicy: .memoryAndDisk))
        await fixture.pipeline.flushPendingWrites()
        await fixture.service.transitionAvatarSession(to: nil)
        #expect(await fixture.service.cachedAvatar(for: "private") == nil)
        #expect(await fixture.disk.read(forKey: "imageCache|private") == nil)
        await #expect(throws: CancellationError.self) { try await fixture.service.loadAvatar(for: "private", maxBytes: 1) }
        await fixture.service.transitionAvatarSession(to: "second")
        #expect(await fixture.service.avatarSessionToken() != token)
        _ = try await fixture.service.loadAvatar(for: "next", maxBytes: 1)
        await fixture.cleanup()
    }

    @Test func authoritativeRemovalInvalidatesBothPathsAndSeed() async throws {
        let fixture = try AvatarServiceFixture()
        let token = await fixture.service.avatarSessionToken()
        let old = avatarTestProfile(thumb: "old", date: 1)
        _ = await fixture.service.observeAvatarProfile(old, previous: nil, token: token)
        _ = try await fixture.service.loadAvatar(AvatarImageRequest(path: "old", representation: .thumbnail, cachePolicy: .memoryAndDisk))
        let removed = avatarTestProfile(thumb: nil, date: 2)
        #expect(await fixture.service.observeAvatarProfile(removed, previous: nil, token: token) == removed)
        #expect(await fixture.service.cachedAvatar(for: "old") == nil)
        #expect(await fixture.disk.read(forKey: "imageCache|old") == nil)
        await #expect(throws: CancellationError.self) { try await fixture.service.loadAvatar(for: "old", maxBytes: 1) }
        #expect(await fixture.service.observeAvatarProfile(old, previous: nil, token: token) == removed)
        #expect(!AvatarImageSource(seedPath: "old").merged(with: removed).hasImagePath)
        await fixture.cleanup()
    }

    @Test func localFileUsesResourceGatesAndDoesNotPersist() async throws {
        let fixture = try AvatarServiceFixture()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fixture.bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try await fixture.service.loadAvatar(for: url.path, maxBytes: 1).size.width == 3)
        #expect(await fixture.calls.limits.isEmpty)
        #expect(await fixture.resources.decode.snapshot().used == 0)
        #expect(await fixture.disk.read(forKey: "imageCache|\(url.path)") == nil)
        await fixture.cleanup()
    }
}

func avatarTestProfile(thumb: String?, date: TimeInterval) -> UserPublicProfile {
    UserPublicProfile(userID: "user", nickname: "사용자", avatarThumbPath: thumb,
                      avatarOriginalPath: thumb.map { $0 + "-original" }, updatedAt: Date(timeIntervalSince1970: date))
}

private struct AvatarServiceFixture {
    let resources = ImagePipelineResources()
    let memory = ImageCacheMemoryStore()
    let folderName = "AvatarTests-\(UUID())"
    let calls = AvatarFetchRecorder()
    let bytes: Data
    let disk: ImageCacheDiskStore
    let pipeline: ImageCachePipeline
    let service: AvatarImageService
    init(failure: Error? = nil,
         originalTimeoutWait: @escaping @Sendable () async throws -> Void = { try await Task.sleep(nanoseconds: 30_000_000_000) },
         beforeFetch: @escaping @Sendable () async throws -> Void = {}) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        bytes = try #require(UIGraphicsImageRenderer(size: CGSize(width: 3, height: 3), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 3, height: 3))
        }.pngData())
        disk = ImageCacheDiskStore(folderName: folderName, resources: resources)
        let data = bytes, recorder = calls
        pipeline = ImageCachePipeline(fetcher: { _, limit in
            await recorder.record(limit)
            try await beforeFetch()
            if let failure { throw failure }
            return data
        }, fileFetcher: { _, limit, url in
            await recorder.record(limit)
            try await beforeFetch()
            if let failure { throw failure }
            try data.write(to: url)
        }, memory: memory, disk: disk, resources: resources,
           promotionEncoding: ImageCachePromotionEncoding(maximumBytes: 4096, encode: { $0.pngData() }))
        service = AvatarImageService(imageStorageRepository: AvatarStorageStub(), pipeline: pipeline, resources: resources,
                                     originalTimeoutWait: originalTimeoutWait)
    }

    func cleanup() async {
        await pipeline.removeAllCachedImages()
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(folderName)
        do {
            let remaining = try FileManager.default.contentsOfDirectory(atPath: url.path)
            #expect(remaining.isEmpty)
            if remaining.isEmpty { try FileManager.default.removeItem(at: url) }
        } catch { Issue.record("테스트 전용 캐시 정리 실패: \(error)") }
    }
}

private actor AvatarFetchRecorder {
    var limits: [Int] = []
    func record(_ limit: Int) { limits.append(limit) }
}

private final class AvatarStorageStub: FirebaseImageStorageRepositoryProtocol {
    func uploadImage(sha: String, uid: String, type: ImageLocation, thumbData: Data, originalFileURL: URL, contentType: String) async throws -> (avatarThumbPath: String, avatarPath: String) { throw URLError(.unsupportedURL) }
    func uploadPairsToRoomMessage(_ pairs: [ProcessedImage], roomID: String, messageID: String, cacheTTLThumbDays: Int, cacheTTLOriginalDays: Int, cleanupTemp: Bool, onProgress: ((Double) -> Void)?) async throws -> [OutPick.Attachment] { throw URLError(.unsupportedURL) }
    func fetchImageDataFromStorage(image: String, location: ImageLocation, maxBytes: Int) async throws -> Data { throw URLError(.unsupportedURL) }
    func fetchImageFromStorage(image: String, location: ImageLocation) async throws -> UIImage { throw URLError(.unsupportedURL) }
    func fetchImagesFromStorage(from imagePaths: [String], location: ImageLocation, createdDate: Date) async throws -> [UIImage] { throw URLError(.unsupportedURL) }
    func prefetchImages(paths: [String], location: ImageLocation, createdDate: Date) {}
    func deleteImageFromStorage(path: String) {}
    func setDataFallbackLimitMB(_ mb: Int) {}
}
