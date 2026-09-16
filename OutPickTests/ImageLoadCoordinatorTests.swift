import Foundation
import Testing
import UIKit
@testable import OutPick

@Suite
struct ImageLoadCoordinatorTests {
    @Test func cancellationBeforeRegistrationDoesNotStartWork() async {
        let entryGate = ImageTestGate()
        let (coordinator, _, disk) = makeCoordinator()
        let request = ImageRequest(path: "pre-cancelled", work: .load(maxBytes: 100))
        let task = Task {
            await entryGate.wait()
            return try await coordinator.value(for: request, priority: .visible, storePolicy: .memoryOnly) { _ in
                Issue.record("등록 전에 취소된 요청은 작업을 시작하면 안 됩니다.")
                return ImageLoadValue(image: nil)
            }
        }
        task.cancel()
        await entryGate.open()
        await expectCancelled(task)
        #expect(await coordinator.consumerCount(for: request) == 0)
        await disk.removeAll()
    }

    @Test func simultaneousConsumersRunOneOperationAndPromotePriority() async throws {
        let gate = ImageTestGate()
        let demand = ImageTestCountSignal()
        let starts = ImageTestCountSignal()
        let (coordinator, _, disk) = makeCoordinator(demand: demand)
        let request = ImageRequest(path: "shared", work: .load(maxBytes: 100))
        let tasks = (0..<20).map { index in
            Task {
                try await coordinator.value(for: request, priority: index == 19 ? .visible : .prefetch, storePolicy: .memoryOnly) { _ in
                    await starts.record(1)
                    await gate.wait()
                    return ImageLoadValue(image: Self.image(width: 3))
                }
            }
        }
        await demand.wait(for: 20)
        #expect(await coordinator.priority(for: request) == .visible)
        await gate.open()
        for task in tasks { #expect(try await task.value.image?.size.width == 3) }
        #expect(await starts.total == 1)
        #expect(await coordinator.consumerCount(for: request) == 0)
        await disk.removeAll()
    }

    @Test func cancellingOneConsumerDoesNotCancelAnother() async throws {
        let gate = ImageTestGate()
        let demand = ImageTestCountSignal()
        let (coordinator, _, disk) = makeCoordinator(demand: demand)
        let request = ImageRequest(path: "cancel-one", work: .load(maxBytes: 100))
        let operation: @Sendable (UInt64) async throws -> ImageLoadValue = { _ in
            await gate.wait()
            try Task.checkCancellation()
            return ImageLoadValue(image: Self.image(width: 4))
        }
        let first = Task { try await coordinator.value(for: request, priority: .prefetch, storePolicy: .memoryOnly, operation: operation) }
        let second = Task { try await coordinator.value(for: request, priority: .visible, storePolicy: .memoryOnly, operation: operation) }
        await demand.wait(for: 2)
        first.cancel()
        await expectCancelled(first)
        #expect(await coordinator.consumerCount(for: request) == 1)
        await gate.open()
        #expect(try await second.value.image?.size.width == 4)
        await disk.removeAll()
    }

    @Test func oldCompletionCannotRemoveReplacementJob() async throws {
        let oldGate = ImageTestGate()
        let newGate = ImageTestGate()
        let oldStarted = ImageTestCountSignal()
        let newStarted = ImageTestCountSignal()
        let oldFinished = ImageTestCountSignal()
        let (coordinator, _, disk) = makeCoordinator()
        let request = ImageRequest(path: "late", work: .load(maxBytes: 100))
        let old = Task {
            try await coordinator.value(for: request, priority: .visible, storePolicy: .memoryOnly) { _ in
                await oldStarted.record(1)
                await oldGate.wait() // 취소를 무시하고 늦게 반환하는 SDK를 재현한다.
                return ImageLoadValue(image: Self.image(width: 1), release: { await oldFinished.record(1) })
            }
        }
        await oldStarted.wait(for: 1)
        old.cancel()
        await expectCancelled(old)
        let new = Task {
            try await coordinator.value(for: request, priority: .visible, storePolicy: .memoryOnly) { _ in
                await newStarted.record(1)
                await newGate.wait()
                return ImageLoadValue(image: Self.image(width: 2))
            }
        }
        await newStarted.wait(for: 1)
        await oldGate.open()
        await oldFinished.wait(for: 1)
        #expect(await coordinator.consumerCount(for: request) == 1)
        await newGate.open()
        #expect(try await new.value.image?.size.width == 2)
        await disk.removeAll()
    }

    @Test func replacingImageRejectsLateDownloadAndItsDiskWrite() async throws {
        let gate = ImageTestGate()
        let started = ImageTestCountSignal()
        let finished = ImageTestCountSignal()
        let (coordinator, memory, disk) = makeCoordinator()
        let request = ImageRequest(path: "overwrite", work: .load(maxBytes: 100))
        let old = Task {
            try await coordinator.value(for: request, priority: .visible, storePolicy: .memoryAndDisk) { _ in
                await started.record(1)
                await gate.wait()
                return ImageLoadValue(image: Self.image(width: 1), downloadedData: Data([1]), release: { await finished.record(1) })
            }
        }
        await started.wait(for: 1)
        try await coordinator.store(image: Self.image(width: 2), data: Data([2]), path: request.path)
        await expectCancelled(old)
        await gate.open()
        await finished.wait(for: 1)
        #expect(memory.image(forKey: request.cacheKey)?.size.width == 2)
        // coordinator의 현재 세대는 cache-only 작업에 전달된다.
        let diskValue = try await coordinator.value(for: ImageRequest(path: request.path, work: .cache), priority: .visible, storePolicy: .memoryOnly) { revision in
            #expect(await disk.read(forKey: request.cacheKey, revision: revision) == Data([2]))
            return ImageLoadValue(image: nil)
        }
        #expect(diskValue.image == nil)
        await coordinator.removeAll()
    }

    @Test func visibleJoinUpgradesActiveMemoryOnlyJobToDiskStorage() async throws {
        let gate = ImageTestGate()
        let demand = ImageTestCountSignal()
        let (coordinator, _, disk) = makeCoordinator(demand: demand)
        let request = ImageRequest(path: "persist", work: .load(maxBytes: 100))
        let operation: @Sendable (UInt64) async throws -> ImageLoadValue = { _ in
            await gate.wait()
            return ImageLoadValue(image: Self.image(width: 3), downloadedData: Data([3]))
        }
        let first = Task { try await coordinator.value(for: request, priority: .prefetch, storePolicy: .memoryOnly, operation: operation) }
        await demand.wait(for: 1)
        let second = Task { try await coordinator.value(for: request, priority: .visible, storePolicy: .memoryAndDisk, operation: operation) }
        await demand.wait(for: 2)
        await gate.open()
        _ = try await first.value
        _ = try await second.value
        await coordinator.flushPendingWrites()
        #expect(await disk.read(forKey: request.cacheKey) == Data([3]))
        await coordinator.removeAll()
    }

    @Test func incompatibleDownloadLimitsUseSeparateJobs() async throws {
        let gate = ImageTestGate()
        let starts = ImageTestCountSignal()
        let (coordinator, _, disk) = makeCoordinator()
        let operation: @Sendable (UInt64) async throws -> ImageLoadValue = { _ in
            await starts.record(1)
            await gate.wait()
            return ImageLoadValue(image: Self.image(width: 1))
        }
        let small = Task { try await coordinator.value(for: ImageRequest(path: "limit", work: .load(maxBytes: 1)), priority: .visible, storePolicy: .memoryOnly, operation: operation) }
        let large = Task { try await coordinator.value(for: ImageRequest(path: "limit", work: .load(maxBytes: 2)), priority: .visible, storePolicy: .memoryOnly, operation: operation) }
        await starts.wait(for: 2)
        await gate.open()
        _ = try await small.value
        _ = try await large.value
        #expect(await starts.total == 2)
        await disk.removeAll()
    }

    @Test(arguments: [false, true]) func removalRejectsLateResult(clearAll: Bool) async throws {
        let gate = ImageTestGate()
        let started = ImageTestCountSignal()
        let finished = ImageTestCountSignal()
        let (coordinator, memory, _) = makeCoordinator()
        let request = ImageRequest(path: "removed", work: .load(maxBytes: 100))
        let task = Task {
            try await coordinator.value(for: request, priority: .visible, storePolicy: .memoryAndDisk) { _ in
                await started.record(1)
                await gate.wait()
                return ImageLoadValue(image: Self.image(width: 1), downloadedData: Data([1]), release: { await finished.record(1) })
            }
        }
        await started.wait(for: 1)
        if clearAll { await coordinator.removeAll() } else { await coordinator.remove(path: request.path) }
        await expectCancelled(task)
        await gate.open()
        await finished.wait(for: 1)
        #expect(memory.image(forKey: request.cacheKey) == nil)
        #expect(await coordinator.consumerCount(for: request) == 0)
        await coordinator.removeAll()
    }

    private func makeCoordinator(demand: ImageTestCountSignal? = nil) -> (ImageLoadCoordinator, ImageCacheMemoryStore, ImageCacheDiskStore) {
        let memory = ImageCacheMemoryStore()
        let disk = ImageCacheDiskStore(folderName: "ImageCoordinatorTests-\(UUID())")
        let coordinator = ImageLoadCoordinator(memory: memory, disk: disk, onDemandChange: { _, _, count in
            if let demand { Task { await demand.recordMaximum(count) } }
        })
        return (coordinator, memory, disk)
    }

    private func expectCancelled(_ task: Task<ImageLoadValue, Error>) async {
        do {
            _ = try await task.value
            Issue.record("취소된 소비자는 성공하면 안 됩니다.")
        } catch {
            #expect(error is CancellationError)
        }
    }

    private static func image(width: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: 1)).image { _ in }
    }
}

private actor ImageTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor ImageTestCountSignal {
    private(set) var total = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func record(_ amount: Int) { total += amount; resumeReady() }
    func recordMaximum(_ count: Int) { total = max(total, count); resumeReady() }
    func wait(for count: Int) async {
        if total >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    private func resumeReady() {
        let ready = waiters.filter { $0.0 <= total }
        waiters.removeAll { $0.0 <= total }
        ready.forEach { $0.1.resume() }
    }
}
