import Foundation
import Testing
import UIKit
@testable import OutPick

@MainActor
struct AvatarViewportPrefetchTests {
    @Test func joiningRoomRetriesTransientFailureButNotUnavailablePhoto() async {
        for error in [URLError(.timedOut) as Error, AvatarImageLoadingError.unavailable] {
            let loader = AvatarPrefetchLoader()
            let controller = AvatarImagePrefetchController(load: loader.load)
            controller.update([demand("a")])
            await wait { loader.calls.count == 1 }
            loader.finish(0, error: error)
            await wait { !controller.loadingPaths.contains("a") }
            controller.update([demand("a", policy: .memoryAndDisk)])
            if error is AvatarImageLoadingError {
                await settle()
                #expect(loader.calls.count == 1)
            } else {
                await wait { loader.calls.count == 2 }
                loader.finish(1)
            }
            controller.clear()
        }
    }
    @Test func directionUsesOneAndHalfScreensAheadAndHalfBehind() {
        let viewport = CGRect(x: 0, y: 100, width: 100, height: 100)
        let rows = [0, 60, 140, 260, 330, 360].map {
            AvatarViewportRow(id: "\($0)", path: "\($0)", frame: CGRect(x: 0, y: $0, width: 50, height: 10))
        }
        #expect(Set(AvatarViewportPrefetchPolicy.select(rows: rows, viewport: viewport, direction: 1).map { $0.request.path }) == ["60", "140", "260", "330"])
        #expect(Set(AvatarViewportPrefetchPolicy.select(rows: rows, viewport: viewport, direction: -1).map { $0.request.path }) == ["0", "60", "140"])
    }

    @Test func uniquePathCapMergesPersistentPolicyAndVisibleEvents() {
        let rows = (0..<60).map { index in
            AvatarViewportRow(id: "row\(index)", path: "path\(index / 2)",
                              frame: CGRect(x: 0, y: index * 2, width: 10, height: 2),
                              policy: index % 2 == 0 ? .memoryOnly : .memoryAndDisk)
        }
        let result = AvatarViewportPrefetchPolicy.select(rows: rows, viewport: CGRect(x: 0, y: 0, width: 100, height: 100), direction: 1)
        #expect(result.count == 24)
        #expect(result.allSatisfy { $0.request.cachePolicy == .memoryAndDisk })
        #expect(result[0].visibleIDs == ["row0", "row1"])
    }

    @Test func quickReturnKeepsRequestAndExitCancelsAfterExactlyGrace() async {
        let clock = AvatarPrefetchClock(), loader = AvatarPrefetchLoader()
        let controller = AvatarImagePrefetchController(sleep: { try await clock.sleep($0) }, load: loader.load)
        controller.update([demand("a")])
        await wait { loader.calls.count == 1 }
        controller.update([])
        await wait { await clock.pendingCount == 1 }
        await clock.advance(299_000_000)
        #expect(controller.activePaths == ["a"])
        controller.update([demand("a")])
        #expect(loader.calls.count == 1)
        await wait { await clock.pendingCount == 0 }
        controller.update([])
        await wait { await clock.pendingCount == 1 }
        await clock.advance(299_000_000)
        #expect(controller.activePaths == ["a"])
        await clock.advance(1_000_000)
        await wait { controller.activePaths.isEmpty }
        loader.finish(0)
        controller.clear()
    }

    @Test func failureWaitsForNewVisibleEventWithoutCooldown() async {
        let loader = AvatarPrefetchLoader()
        let controller = AvatarImagePrefetchController(load: loader.load)
        controller.update([demand("a", visible: ["first"])])
        await wait { loader.calls.count == 1 }
        loader.finish(0, error: URLError(.timedOut))
        await wait { !controller.loadingPaths.contains("a") }
        for _ in 0..<10 { controller.update([demand("a", visible: ["first"])]) }
        await settle()
        #expect(loader.calls.count == 1)
        controller.update([demand("a", visible: ["first", "new-message"])])
        await wait { loader.calls.count == 2 }
        loader.finish(1)
        controller.clear()
    }

    @Test func backgroundArrivalDoesNotRetryButVisibleReentryDoes() async {
        let loader = AvatarPrefetchLoader()
        let controller = AvatarImagePrefetchController(load: loader.load)
        controller.update([demand("a")])
        await wait { loader.calls.count == 1 }
        loader.finish(0, error: URLError(.notConnectedToInternet))
        await wait { !controller.loadingPaths.contains("a") }
        controller.update([demand("a")])
        await settle()
        #expect(loader.calls.count == 1)
        controller.update([demand("a", visible: ["visible"])])
        await wait { loader.calls.count == 2 }
        loader.finish(1)
        controller.clear()
    }

    @Test func persistentDemandArrivingDuringLoadPromotesAfterSuccess() async {
        let loader = AvatarPrefetchLoader()
        let controller = AvatarImagePrefetchController(load: loader.load)
        controller.update([demand("a")])
        await wait { loader.calls.count == 1 }
        controller.update([demand("a", policy: .memoryAndDisk)])
        #expect(loader.calls.count == 1)
        loader.finish(0)
        await wait { loader.calls.count == 2 }
        #expect(loader.calls[1].cachePolicy == .memoryAndDisk)
        loader.finish(1)
        controller.clear()
    }

    @Test func screenExitClearsImmediatelyAndLateFailureCannotReplaceNewEntry() async {
        let loader = AvatarPrefetchLoader()
        let controller = AvatarImagePrefetchController(load: loader.load)
        controller.update([demand("a")])
        await wait { loader.calls.count == 1 }
        controller.clear()
        #expect(controller.activePaths.isEmpty)
        controller.update([demand("a")])
        await wait { loader.calls.count == 2 }
        loader.finish(0, error: AvatarImageLoadingError.unavailable)
        await settle()
        controller.update([demand("a", visible: ["new"])])
        #expect(loader.calls.count == 2)
        loader.finish(1)
        controller.clear()
    }

    private func demand(_ path: String, visible: Set<String> = [], policy: AvatarImageCachePolicy = .memoryOnly) -> AvatarViewportDemand {
        AvatarViewportDemand(request: AvatarImageRequest(path: path, representation: .thumbnail, cachePolicy: policy), visibleIDs: visible)
    }
    private func settle() async { for _ in 0..<30 { await Task.yield() } }
    private func wait(_ condition: () async -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !(await condition()), Date() < deadline { await Task.yield() }
        #expect(await condition())
    }
}

@MainActor
private final class AvatarPrefetchLoader {
    var calls: [AvatarImageRequest] = []
    private var pending: [Int: CheckedContinuation<Void, Error>] = [:]
    func load(_ request: AvatarImageRequest) async throws {
        let index = calls.count
        calls.append(request)
        try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func finish(_ index: Int, error: Error? = nil) {
        guard let continuation = pending.removeValue(forKey: index) else { return }
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
}

private actor AvatarPrefetchClock {
    private var now: UInt64 = 0
    private var pending: [UUID: (UInt64, CheckedContinuation<Void, Error>)] = [:]
    var pendingCount: Int { pending.count }
    func sleep(_ duration: UInt64) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { pending[id] = (now + duration, $0) }
        } onCancel: { Task { await self.cancel(id) } }
    }
    func advance(_ duration: UInt64) {
        now += duration
        for id in Array(pending.keys) where pending[id]!.0 <= now { pending.removeValue(forKey: id)?.1.resume() }
    }
    private func cancel(_ id: UUID) { pending.removeValue(forKey: id)?.1.resume(throwing: CancellationError()) }
}
