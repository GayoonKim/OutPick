import Foundation
import Testing
@testable import OutPick

@MainActor
struct LookbookViewportPrefetchTests {
    @Test func viewportUsesScrollDirectionAndLimitsCandidates() {
        let ids = (0..<100).map(String.init)
        var tracker = LookbookViewportTracker()
        let initial = ["10": CGRect(x: 0, y: 0, width: 100, height: 140),
                       "12": CGRect(x: 0, y: 150, width: 100, height: 140)]
        let down = tracker.range(ids: ids, frames: initial, viewportHeight: 300,
                                 columns: 2, estimatedRowStride: 150)
        #expect(down.contains(18))
        #expect(down.contains(4) == false)

        let movedUp = ["10": CGRect(x: 0, y: 150, width: 100, height: 140),
                       "12": CGRect(x: 0, y: 300, width: 100, height: 140)]
        let up = tracker.range(ids: ids, frames: movedUp, viewportHeight: 300,
                               columns: 2, estimatedRowStride: 150)
        #expect(tracker.direction == -1)
        #expect(up.contains(4))
        #expect(up.contains(18) == false)

        _ = tracker.range(ids: ids, frames: ["30": CGRect(x: 0, y: 0, width: 100, height: 140)],
                          viewportHeight: 300, columns: 2, estimatedRowStride: 150)
        #expect(tracker.direction == 1)

        let capped = tracker.range(ids: ids, frames: [:], viewportHeight: 1_000,
                                   columns: 2, estimatedRowStride: 20)
        #expect(capped.count == 24)
    }

    @Test func repeatedDemandDoesNotStartTheSameImageTwice() async throws {
        let recorder = PrefetchRecorder()
        let controller = LookbookImagePrefetchController(graceNanoseconds: 0) { request in
            await recorder.record(request.identity)
        }
        let request = LookbookAssetImageRequest(
            primaryPath: "brands/logo.jpg", secondaryPath: nil,
            remoteURL: nil, sourcePageURL: nil, maxBytes: 1_000_000
        )
        controller.update([request])
        controller.update([request])
        try await waitUntil { await recorder.count == 1 }
        #expect(await recorder.count == 1)
        controller.clear()
    }

    @Test func demandLeavingViewportCancelsAndReentryStartsAgain() async throws {
        let recorder = PrefetchRecorder()
        let controller = LookbookImagePrefetchController(graceNanoseconds: 0) { request in
            await recorder.record(request.identity)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            await recorder.recordCancellation()
        }
        let request = LookbookAssetImageRequest(
            primaryPath: "seasons/cover.jpg", secondaryPath: nil,
            remoteURL: nil, sourcePageURL: nil, maxBytes: 1_000_000
        )
        controller.update([request])
        try await waitUntil { await recorder.count == 1 }
        controller.update([])
        try await waitUntil { await recorder.cancellations == 1 }
        controller.update([request])
        try await waitUntil { await recorder.count == 2 }
        controller.clear()
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        Issue.record("예상한 비동기 상태에 도달하지 못했습니다.")
    }
}

private actor PrefetchRecorder {
    private(set) var count = 0
    private(set) var cancellations = 0
    func record(_ key: String) { count += 1 }
    func recordCancellation() { cancellations += 1 }
}
