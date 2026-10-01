import Foundation
import Testing
@testable import OutPick

struct ChatOriginalFileStoreTests {
    @Test func oneConsumerCancelsWhileOtherKeepsSharedTransferAndLease() async throws {
        let f = try Fixture()
        defer { f.clean() }
        let first = Task { try await f.service.acquireOriginal(f.resource, purpose: .viewing) }
        await f.transport.waitForStart(1)
        let second = Task { try await f.service.acquireOriginal(f.resource, purpose: .saving) }
        try await eventually { await f.store.usage().consumers == 2 }
        first.cancel()
        await expectCancellation(first)
        #expect(await f.store.usage().consumers == 1)
        await f.transport.complete(1)
        let lease = try await second.value
        #expect(lease.isValid)
        #expect(try Data(contentsOf: lease.fileURL) == Data(repeating: 7, count: 8))
        #expect(await f.transport.starts == 1)
        await lease.release()
    }

    @Test func lastCancellationKeepsPermitAndTemporaryFileUntilSDKCompletion() async throws {
        let f = try Fixture()
        defer { f.clean() }
        let task = Task { try await f.service.acquireOriginal(f.resource, purpose: .viewing) }
        await f.transport.waitForStart(1)
        task.cancel()
        await expectCancellation(task)
        #expect(await f.resources.network.snapshot().active == 1)
        #expect(await f.resources.files.snapshot().active == 1)
        #expect(await f.transport.destinationExists(1))
        await f.transport.complete(1)
        try await eventually { await f.store.usage().activeTransfers == 0 }
        #expect(await f.resources.network.snapshot().active == 0)
        #expect(await f.resources.files.snapshot().active == 0)
        #expect(await f.store.usage().temporaryBytes == 0)
        #expect(await f.store.usage().cachedBytes == 0)
    }

    @Test func retryDuringCancelledSDKTransferUsesSeparateFile() async throws {
        let f = try Fixture()
        defer { f.clean() }
        let old = Task { try await f.service.acquireOriginal(f.resource, purpose: .viewing) }
        await f.transport.waitForStart(1)
        old.cancel()
        await expectCancellation(old)
        let next = Task { try await f.service.acquireOriginal(f.resource, purpose: .viewing) }
        await f.transport.waitForStart(2)
        await f.transport.complete(2)
        let lease = try await next.value
        await f.transport.complete(1)
        try await eventually { await f.store.usage().activeTransfers == 0 }
        #expect(FileManager.default.fileExists(atPath: lease.fileURL.path))
        #expect(lease.isValid)
        await lease.release()
    }

    @Test func logoutRejectsLateSuccessButReusesCompletedCacheForSameAccount() async throws {
        let f = try Fixture()
        defer { f.clean() }
        let saved = try await f.load()
        await saved.release()
        let pendingResource = ChatOriginalResource(path: "rooms/test/late.gif")
        let pending = Task { try await f.service.acquireOriginal(pendingResource, purpose: .viewing) }
        await f.transport.waitForStart(2)
        f.service.invalidateSession()
        await f.transport.complete(2)
        await expectCancellation(pending)
        try await eventually { await f.store.usage().activeTransfers == 0 }
        let same = f.makeService(account: "A")
        let hit = try #require(try await same.cachedOriginal(f.resource))
        #expect(hit.isValid)
        #expect(try await same.cachedOriginal(pendingResource) == nil)
        let other = f.makeService(account: "B")
        #expect(try await other.cachedOriginal(f.resource) == nil)
        await hit.release()
        #expect(await f.store.usage().cachedBytes == 8)
    }

    @Test func deletionInvalidatesLeasesAndBlocksLateDownloadForAllVersions() async throws {
        let f = try Fixture()
        defer { f.clean() }
        let existing = try await f.load()
        let newer = ChatOriginalResource(path: f.resource.path, version: "new")
        let task = Task { try await f.service.acquireOriginal(newer, purpose: .saving) }
        await f.transport.waitForStart(2)
        await f.service.removeOriginal(path: f.resource.path)
        #expect(!existing.isValid)
        #expect(FileManager.default.fileExists(atPath: existing.fileURL.path))
        await f.transport.complete(2)
        await expectCancellation(task)
        await existing.release()
        try await eventually { await f.store.usage().activeTransfers == 0 }
        #expect(!FileManager.default.fileExists(atPath: existing.fileURL.path))
        #expect(await f.store.usage().cachedBytes == 0)
        do { _ = try await f.service.acquireOriginal(newer, purpose: .viewing); Issue.record("삭제 원본 재요청 허용") }
        catch is CancellationError {} catch { Issue.record("예상하지 못한 오류: \(error)") }
    }

    @Test func pinnedFileSurvivesPressureAndOverflowFileDisappearsAfterLastLease() async throws {
        let f = try Fixture(capacity: 8)
        defer { f.clean() }
        let first = try await f.load()
        let otherResource = ChatOriginalResource(path: "rooms/test/other.jpg")
        let task = Task { try await f.service.acquireOriginal(otherResource, purpose: .saving) }
        await f.transport.waitForStart(2)
        await f.transport.complete(2)
        let other = try await task.value
        let shared = try #require(try await f.service.cachedOriginal(otherResource))
        #expect(await f.store.usage().cachedBytes == 8)
        #expect(await f.store.usage().temporaryBytes == 8)
        #expect(FileManager.default.fileExists(atPath: first.fileURL.path))
        await other.release()
        #expect(FileManager.default.fileExists(atPath: shared.fileURL.path))
        await shared.release()
        #expect(!FileManager.default.fileExists(atPath: other.fileURL.path))
        #expect(await f.resources.files.snapshot().active == 0)
        await first.release()
    }

    @Test func budgetIsSharedAcrossAccountsAndEvictsOnlyUnpinnedCache() async throws {
        let f = try Fixture(capacity: 8)
        defer { f.clean() }
        let first = try await f.load()
        await first.release()
        let b = f.makeService(account: "B")
        let task = Task { try await b.acquireOriginal(f.resource, purpose: .viewing) }
        await f.transport.waitForStart(2)
        await f.transport.complete(2)
        let second = try await task.value
        #expect(try await f.service.cachedOriginal(f.resource) == nil)
        #expect(await f.store.usage().cachedBytes == 8)
        await second.release()
    }

    @Test func freshStoreReusesOnlyItsOwnOriginalNamespace() async throws {
        let f = try Fixture()
        defer { f.clean() }
        let first = try await f.load()
        await first.release()
        let restored = ChatOriginalFileStore(root: f.root, resources: f.resources)
        let service = ChatOriginalFileService(accountID: "A", store: restored, transport: f.transport)
        let hit = try #require(try await service.cachedOriginal(f.resource))
        #expect(hit.fileURL == first.fileURL)
        #expect(await f.transport.starts == 1)
        await hit.release()
    }

    @Test func expiryDuringAnInFlightDownloadRejectsTheLateFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OriginalExpiry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = OriginalTestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let resources = ImagePipelineResources()
        let transport = OriginalTransportBarrier()
        let store = ChatOriginalFileStore(root: root, resources: resources, now: { clock.now })
        let expiresAt = clock.now.addingTimeInterval(5)
        let service = ChatOriginalFileService(accountID: "A", store: store, transport: transport)
        let resource = ChatOriginalResource(path: "rooms/test/expiring.gif", version: "g1", mediaExpiresAt: expiresAt)
        let task = Task { try await service.acquireOriginal(resource, purpose: .viewing) }
        await transport.waitForStart(1)

        clock.set(expiresAt)
        #expect(await store.removeExpired(at: expiresAt))
        await expectCancellation(task)
        #expect(await store.usage().activeTransfers == 1)
        await transport.complete(1)

        try await eventually { await store.usage().activeTransfers == 0 }
        #expect(await store.usage().cachedBytes == 0)
        #expect(await store.usage().temporaryBytes == 0)
    }

    @Test func expiredPinnedOriginalIsHiddenImmediatelyAndRemovedAfterRelease() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OriginalPinnedExpiry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = OriginalTestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let resources = ImagePipelineResources()
        let transport = OriginalTransportBarrier()
        let store = ChatOriginalFileStore(root: root, resources: resources, now: { clock.now })
        let expiresAt = clock.now.addingTimeInterval(30)
        let service = ChatOriginalFileService(accountID: "A", store: store, transport: transport)
        let resource = ChatOriginalResource(path: "rooms/test/pinned.mp4", version: "g1", mediaExpiresAt: expiresAt)
        let task = Task { try await service.acquireOriginal(resource, purpose: .saving) }
        await transport.waitForStart(1)
        await transport.complete(1)
        let lease = try await task.value

        clock.set(expiresAt)
        #expect(!lease.isValid)
        #expect(!(await store.removeExpired(at: expiresAt)))
        #expect(FileManager.default.fileExists(atPath: lease.fileURL.path))

        await lease.release()
        #expect(await store.removeExpired(at: expiresAt))
        #expect(!FileManager.default.fileExists(atPath: lease.fileURL.path))
    }

    @Test func photoLibrarySubmissionProtectsLeaseAcrossExpiryUntilCallbackRelease() async throws {
        let validity = OriginalTestValidity()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SubmittedPhoto-\(UUID().uuidString)")
        let lease = ChatOriginalFileLease(fileURL: url, isValid: { validity.isValid }, release: {})

        #expect(lease.beginPhotoLibrarySubmission())
        validity.invalidate()
        #expect(lease.isValid)

        await lease.release()
        #expect(!lease.isValid)
    }

    @Test func expiredDiskEntryIsPurgedAfterAStoreRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OriginalRestartExpiry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = OriginalTestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let resources = ImagePipelineResources()
        let transport = OriginalTransportBarrier()
        let store = ChatOriginalFileStore(root: root, resources: resources, now: { clock.now })
        let expiresAt = clock.now.addingTimeInterval(30)
        let service = ChatOriginalFileService(
            accountID: "A",
            store: store,
            transport: transport
        )
        let resource = ChatOriginalResource(path: "rooms/test/restart.jpg", version: "g1", mediaExpiresAt: expiresAt)
        let task = Task { try await service.acquireOriginal(resource, purpose: .viewing) }
        await transport.waitForStart(1)
        await transport.complete(1)
        let lease = try await task.value
        let cachedURL = lease.fileURL
        await lease.release()

        clock.set(expiresAt)
        let restored = ChatOriginalFileStore(root: root, resources: resources, now: { clock.now })
        #expect(await restored.removeExpired(at: expiresAt))
        #expect(!FileManager.default.fileExists(atPath: cachedURL.path))
        #expect(await restored.usage().cachedBytes == 0)
    }

    @Test func diskCommitReplacesAnExistingKeyAndItsExpiryMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OriginalReplace-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try ChatOriginalFileDisk(root: root)
        let resource = ChatOriginalResource(path: "rooms/test/replaced.jpg", version: "g1")
        let key = ChatOriginalFileKey(accountID: "A", resource: resource)
        let firstExpiry = Date(timeIntervalSince1970: 2_000_000_000)
        let secondExpiry = firstExpiry.addingTimeInterval(60)
        let firstTemporary = disk.temporaryURL(ext: key.ext)
        try Data([1, 2, 3]).write(to: firstTemporary)
        let firstURL = try disk.commit(firstTemporary, key: key, mediaExpiresAt: firstExpiry)
        let secondTemporary = disk.temporaryURL(ext: key.ext)
        try Data([4, 5, 6, 7]).write(to: secondTemporary)
        let secondURL = try disk.commit(secondTemporary, key: key, mediaExpiresAt: secondExpiry)

        #expect(firstURL == secondURL)
        #expect(try Data(contentsOf: secondURL) == Data([4, 5, 6, 7]))
        let restored = try #require(disk.inventory().first)
        #expect(restored.4 == secondExpiry)
    }

    @Test func transferFailureCleansPartialFileAndAllowsExplicitRetry() async throws {
        let f = try Fixture()
        defer { f.clean() }
        let task = Task { try await f.service.acquireOriginal(f.resource, purpose: .viewing) }
        await f.transport.waitForStart(1)
        await f.transport.complete(1, failure: true)
        do { _ = try await task.value; Issue.record("전송 실패 누락") } catch {}
        #expect(await f.store.usage().temporaryBytes == 0)
        let retry = Task { try await f.service.acquireOriginal(f.resource, purpose: .saving) }
        await f.transport.waitForStart(2)
        await f.transport.complete(2)
        let value = try await retry.value
        await value.release()
    }

    @Test func accountDeletionScrubInvalidatesActiveFileAndLateWriter() async throws {
        let f = try Fixture()
        defer { f.clean() }
        let lease = try await f.load()
        let task = Task { try await f.service.acquireOriginal(ChatOriginalResource(path: "rooms/test/late.mp4"), purpose: .saving) }
        await f.transport.waitForStart(2)
        await f.store.removeAll()
        #expect(!lease.isValid)
        await f.transport.complete(2)
        await expectCancellation(task)
        await lease.release()
        try await eventually { await f.store.usage().activeTransfers == 0 }
        #expect(await f.store.usage().combinedBytes == 0)
    }

    private func expectCancellation(_ task: Task<ChatOriginalFileLease, Error>) async {
        do { let value = try await task.value; await value.release(); Issue.record("취소 결과 누락") }
        catch is CancellationError {} catch { Issue.record("예상하지 못한 오류: \(error)") }
    }

    private func eventually(_ predicate: () async -> Bool) async throws {
        for _ in 0..<10_000 {
            if await predicate() { return }
            await Task.yield()
        }
        throw URLError(.timedOut)
    }

    private struct Fixture {
        let root: URL
        let resources = ImagePipelineResources()
        let transport = OriginalTransportBarrier()
        let store: ChatOriginalFileStore
        let service: ChatOriginalFileService
        let resource = ChatOriginalResource(path: "rooms/test/original.jpg")

        init(capacity: Int = 64) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("OriginalTests-\(UUID().uuidString)")
            store = ChatOriginalFileStore(root: root, capacity: capacity, resources: resources)
            service = ChatOriginalFileService(accountID: "A", store: store, transport: transport)
        }

        func makeService(account: String) -> ChatOriginalFileService {
            ChatOriginalFileService(accountID: account, store: store, transport: transport)
        }

        func load() async throws -> ChatOriginalFileLease {
            let task = Task { try await service.acquireOriginal(resource, purpose: .viewing) }
            await transport.waitForStart(1)
            await transport.complete(1)
            return try await task.value
        }

        func clean() { try? FileManager.default.removeItem(at: root) }
    }
}

private final class OriginalTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) { self.value = value }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ value: Date) {
        lock.lock()
        self.value = value
        lock.unlock()
    }
}

private final class OriginalTestValidity: @unchecked Sendable {
    private let lock = NSLock()
    private var value = true
    var isValid: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func invalidate() { lock.lock(); value = false; lock.unlock() }
}

private actor OriginalTransportBarrier: ChatOriginalFileTransport {
    private(set) var starts = 0
    private var destinations: [Int: URL] = [:]
    private var completions: [Int: CheckedContinuation<Void, Error>] = [:]
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []

    func download(_ resource: ChatOriginalResource, to destination: URL) async throws {
        starts += 1
        let index = starts
        destinations[index] = destination
        try Data([0]).write(to: destination)
        try await withCheckedThrowingContinuation { continuation in
            completions[index] = continuation
            let ready = observers.filter { $0.0 <= starts }
            observers.removeAll { $0.0 <= starts }
            ready.forEach { $0.1.resume() }
        }
        // SDK 취소 후에도 늦게 성공하는 최악의 순서를 의도적으로 재현한다.
        try Data(repeating: 7, count: 8).write(to: destination)
    }

    func waitForStart(_ count: Int) async {
        if starts >= count { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }

    func complete(_ index: Int, failure: Bool = false) {
        let continuation = completions.removeValue(forKey: index)
        if failure { continuation?.resume(throwing: URLError(.networkConnectionLost)) }
        else { continuation?.resume() }
    }

    func destinationExists(_ index: Int) -> Bool {
        destinations[index].map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }
}
