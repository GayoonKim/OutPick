import XCTest
import UIKit
@testable import OutPick

@MainActor
final class ChatMediaViewportControllerTests: XCTestCase {
    func testUnlimitedPreparationStartsAllCandidatesAndCancelsAll() async {
        let started = expectation(description: "상한 해제 후보 시작")
        let cancelled = expectation(description: "모든 준비 취소")
        started.expectedFulfillmentCount = 5
        cancelled.expectedFulfillmentCount = 5
        var pending: [CheckedContinuation<Void, Never>] = []
        let controller = ChatMediaViewportController(load: { _, _ in
            XCTFail("디스크 준비에서 다운로드 금지")
            return UIImage()
        }, canPrepareDisk: { true }, prepareDisk: { _ in
            await withTaskCancellationHandler {
                await withCheckedContinuation { pending.append($0); started.fulfill() }
            } onCancel: { cancelled.fulfill() }
        })
        controller.prepareDiskBeforeLayout(paths: ["A", "B", "C", "D", "E"])
        await fulfillment(of: [started], timeout: 1)
        controller.stopDiskPreparation()
        await fulfillment(of: [cancelled], timeout: 1)
        pending.forEach { $0.resume() }
    }

    func testTwoPreparationsRunTogetherButBudgetStopsRefill() async {
        let started = expectation(description: "두 장 동시 준비")
        started.expectedFulfillmentCount = 2
        var pending: [String: CheckedContinuation<Void, Never>] = [:]
        var allowed = true
        var calls: [String] = []
        let controller = ChatDiskPreparationController(maxConcurrent: 2, canPrepare: { allowed }, prepare: { path in
            calls.append(path)
            await withCheckedContinuation { pending[path] = $0; started.fulfill() }
        })
        controller.update(paths: ["A", "B", "C"])
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(Set(calls), Set(["A", "B"]))
        allowed = false
        pending["A"]?.resume()
        pending["B"]?.resume()
        controller.update(paths: ["C", "B", "A"])
        controller.suspend()
        XCTAssertEqual(calls.count, 2)
    }

    func testPreparationStartsBeforeViewportResumeAndStopsOnDisappearance() async {
        let started = expectation(description: "배치와 viewport 활성화 전 디스크 준비")
        let cancelled = expectation(description: "화면 이탈 시 준비 취소")
        var pending: CheckedContinuation<Void, Never>?
        let controller = ChatMediaViewportController(load: { _, _ in
            XCTFail("초기 준비에서 다운로드 로더 사용 금지")
            return UIImage()
        }, canPrepareDisk: { true }, prepareDisk: { path in
            XCTAssertEqual(path, "early")
            await withTaskCancellationHandler {
                await withCheckedContinuation { pending = $0; started.fulfill() }
            } onCancel: { cancelled.fulfill() }
        })
        controller.prepareDiskBeforeLayout(paths: ["early"])
        await fulfillment(of: [started], timeout: 1)
        controller.stopDiskPreparation()
        await fulfillment(of: [cancelled], timeout: 1)
        pending?.resume()
    }

    func testDiskPreparationUsesLatestOrderAndStopsAtBudget() async {
        let first = expectation(description: "첫 준비")
        let second = expectation(description: "이동 후 가까운 사진")
        var pending: CheckedContinuation<Void, Never>?
        var calls: [String] = []
        var allowed = true
        let controller = ChatDiskPreparationController(canPrepare: { allowed }, prepare: { path in
            calls.append(path)
            if path == "A" {
                await withCheckedContinuation { pending = $0; first.fulfill() }
            } else {
                allowed = false
                second.fulfill()
            }
        })
        controller.update(paths: ["A", "B", "C"])
        await fulfillment(of: [first], timeout: 1)
        controller.update(paths: ["C", "A", "B"])
        pending?.resume()
        await fulfillment(of: [second], timeout: 1)
        XCTAssertEqual(calls, ["A", "C"])
        controller.suspend()
    }

    func testDiskPreparationSuspendCancelsAndDoesNotStartNext() async {
        let started = expectation(description: "준비 시작")
        let cancelled = expectation(description: "방 이탈 취소")
        var pending: CheckedContinuation<Void, Never>?
        var calls: [String] = []
        let controller = ChatDiskPreparationController(canPrepare: { true }, prepare: { path in
            calls.append(path)
            await withTaskCancellationHandler {
                await withCheckedContinuation { pending = $0; started.fulfill() }
            } onCancel: { cancelled.fulfill() }
        })
        controller.update(paths: ["A", "B"])
        await fulfillment(of: [started], timeout: 1)
        controller.suspend()
        await fulfillment(of: [cancelled], timeout: 1)
        pending?.resume()
        XCTAssertEqual(calls, ["A"])
    }

    func testFastScrollCancelsOutsideDemandWithoutGrace() async {
        let started = expectation(description: "요청 시작")
        let cancelled = expectation(description: "빠른 스크롤 범위 밖 즉시 취소")
        var pending: CheckedContinuation<UIImage, Error>?
        let controller = ChatMediaViewportController(load: { _, _ in
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    pending = continuation
                    started.fulfill()
                }
            } onCancel: { cancelled.fulfill() }
        }, delay: { XCTFail("빠른 이탈에는 유예를 시작하지 않음") })
        controller.resume()
        update(controller, priority: .visible)
        await fulfillment(of: [started], timeout: 1)
        controller.update(items: [item()], demands: [:], validIDs: ["item"], cancelOutsideImmediately: true)
        await fulfillment(of: [cancelled], timeout: 1)
        pending?.resume(returning: UIImage())
        controller.endSession()
    }

    func testMemoryHitOnReentryPublishesImageWithoutLoadingOrAsyncRequest() {
        let image = UIImage()
        var lookups: [String] = []
        var images = 0
        let controller = ChatMediaViewportController(cached: { path in
            lookups.append(path)
            return image
        }, load: { _, _ in
            XCTFail("메모리 hit는 비동기 요청 없이 표시해야 합니다.")
            return UIImage()
        })
        controller.onChange = { _, _, state in
            guard case .image(let displayed) = state else { XCTFail("hit 앞에 loading/idle을 내보내면 안 됩니다."); return }
            XCTAssertTrue(displayed === image)
            images += 1
        }
        controller.resume()
        update(controller, priority: .visible)
        controller.endSession()
        controller.resume()
        update(controller, priority: .visible)
        XCTAssertEqual(lookups, ["thumb", "thumb"])
        XCTAssertEqual(images, 2)
        controller.endSession()
    }

    private func item(_ path: String = "thumb") -> ChatMediaViewportItem {
        ChatMediaViewportItem(id: "item", path: path, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    private func update(_ controller: ChatMediaViewportController, priority: ImageRequestPriority?, path: String = "thumb") {
        controller.update(items: [item(path)], demands: priority.map { ["item": $0] } ?? [:], validIDs: ["item"])
    }

    func testPromotionJoinsSharedDownloadAndSuspensionPreservesOtherConsumer() async throws {
        let disk = ImageCacheDiskStore(folderName: "ChatViewportTests-\(UUID())")
        let registered = expectation(description: "뷰어와 선로딩 합류")
        let promoted = expectation(description: "visible 소비자 추가")
        let released = expectation(description: "뷰어 소비자만 유지")
        let releaseProbe = ViewportReleaseProbe()
        let coordinator = ImageLoadCoordinator(memory: ImageCacheMemoryStore(), disk: disk, onDemandChange: { _, priority, count in
            let events = releaseProbe.record(count: count)
            if events.joined { registered.fulfill() }
            if events.promoted && priority == .visible { promoted.fulfill() }
            if events.released { released.fulfill() }
        })
        let request = ImageRequest(path: "shared", work: .load(maxBytes: 100))
        let gate = ViewportImageGate()
        let operation: @Sendable (UInt64) async throws -> ImageLoadValue = { _ in
            await gate.started()
            await gate.wait()
            try Task.checkCancellation()
            return ImageLoadValue(image: UIImage())
        }
        let viewer = Task {
            try await coordinator.value(for: request, priority: .prefetch, storePolicy: .memoryOnly, operation: operation)
        }
        let controller = ChatMediaViewportController { _, priority in
            let value = try await coordinator.value(for: request, priority: priority, storePolicy: .memoryOnly, operation: operation)
            return try XCTUnwrap(value.image)
        }
        controller.resume()
        update(controller, priority: .prefetch)
        await fulfillment(of: [registered], timeout: 1)
        update(controller, priority: .visible)
        await fulfillment(of: [promoted], timeout: 1)
        controller.suspend()
        await fulfillment(of: [released], timeout: 1)
        let remaining = await coordinator.consumerCount(for: request)
        XCTAssertEqual(remaining, 1)
        await gate.open()
        _ = try await viewer.value
        let starts = await gate.starts
        XCTAssertEqual(starts, 1)
        controller.endSession()
        await disk.removeAll()
    }

    func testFailureRetriesOnlyAfterActualReappearanceAndNewSession() async {
        var requests = 0
        let controller = ChatMediaViewportController { _, _ in
            requests += 1
            throw URLError(.notConnectedToInternet)
        }
        controller.resume()
        var failed = expectation(description: "실패")
        controller.onChange = { _, _, state in if case .failed = state { failed.fulfill() } }
        update(controller, priority: .visible)
        await fulfillment(of: [failed], timeout: 1)
        controller.onChange = nil
        update(controller, priority: .visible)
        controller.suspend()
        controller.resume()
        update(controller, priority: .visible)
        XCTAssertEqual(requests, 1)

        update(controller, priority: .prefetch)
        failed = expectation(description: "재등장 실패")
        controller.onChange = { _, _, state in if case .failed = state { failed.fulfill() } }
        update(controller, priority: .visible)
        await fulfillment(of: [failed], timeout: 1)
        XCTAssertEqual(requests, 2)

        controller.endSession()
        controller.resume()
        failed = expectation(description: "방 재진입 실패")
        update(controller, priority: .visible)
        await fulfillment(of: [failed], timeout: 1)
        XCTAssertEqual(requests, 3)
        controller.endSession()
    }

    func testFailedPrefetchRetriesOnFirstVisibility() async {
        var priorities: [ImageRequestPriority] = []
        let controller = ChatMediaViewportController { _, priority in
            priorities.append(priority)
            throw URLError(.fileDoesNotExist)
        }
        controller.resume()
        var failed = expectation(description: "선로딩 실패")
        controller.onChange = { _, _, state in if case .failed = state { failed.fulfill() } }
        update(controller, priority: .prefetch)
        await fulfillment(of: [failed], timeout: 1)
        failed = expectation(description: "첫 표시 재시도")
        update(controller, priority: .visible)
        await fulfillment(of: [failed], timeout: 1)
        XCTAssertEqual(priorities, [.prefetch, .visible])
        controller.endSession()
    }

    func testTransportCancellationDoesNotBecomeFailureInSameEpisode() async {
        var requests = 0
        let idle = expectation(description: "취소는 idle")
        let loaded = expectation(description: "같은 표시 회차에서 다시 요청")
        let controller = ChatMediaViewportController { _, _ in
            requests += 1
            if requests == 1 { throw CancellationError() }
            return UIImage()
        }
        controller.onChange = { _, _, state in
            if case .idle = state { idle.fulfill() }
            if case .image = state { loaded.fulfill() }
            if case .failed = state { XCTFail("취소를 실패로 기록하면 안 됩니다.") }
        }
        controller.resume()
        update(controller, priority: .visible)
        await fulfillment(of: [idle], timeout: 1)
        update(controller, priority: .visible)
        await fulfillment(of: [loaded], timeout: 1)
        XCTAssertEqual(requests, 2)
        controller.endSession()
    }

    func testDeletedItemCancelsImmediatelyAndRejectsLateImage() async {
        let started = expectation(description: "요청 등록")
        let cancelled = expectation(description: "삭제 즉시 취소")
        let stale = expectation(description: "삭제 이후 응답 차단")
        stale.isInverted = true
        var pending: CheckedContinuation<UIImage, Error>?
        let controller = ChatMediaViewportController(load: { _, _ in
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    pending = continuation
                    started.fulfill()
                }
            } onCancel: { cancelled.fulfill() }
        }, delay: { XCTFail("삭제에는300ms 유예를 적용하지 않습니다.") })
        controller.onChange = { _, _, state in if case .image = state { stale.fulfill() } }
        controller.resume()
        update(controller, priority: .visible)
        await fulfillment(of: [started], timeout: 1)
        controller.update(items: [], demands: [:], validIDs: [])
        await fulfillment(of: [cancelled], timeout: 1)
        pending?.resume(returning: UIImage())
        await fulfillment(of: [stale], timeout: 0.05)
        controller.endSession()
    }

    func testReturningDuringGraceKeepsRunningRequest() async {
        var pending: [String: CheckedContinuation<UIImage, Error>] = [:]
        var release: CheckedContinuation<Void, Error>?
        let started = expectation(description: "첫 요청")
        let delayStarted = expectation(description: "해제 예약")
        let controller = ChatMediaViewportController(load: { path, _ in
            try await withCheckedThrowingContinuation { continuation in
                pending[path] = continuation
                if path == "thumb" { started.fulfill() }
            }
        }, delay: {
            try await withCheckedThrowingContinuation { continuation in
                release = continuation
                delayStarted.fulfill()
            }
        })
        controller.resume()
        update(controller, priority: .visible)
        await fulfillment(of: [started], timeout: 1)
        update(controller, priority: nil)
        await fulfillment(of: [delayStarted], timeout: 1)
        update(controller, priority: .visible)
        release?.resume()
        let loaded = expectation(description: "유예 중 복귀는 진행 요청 유지")
        let photo = UIImage()
        controller.onChange = { _, _, state in
            if case .image(let image) = state { XCTAssertTrue(image === photo); loaded.fulfill() }
        }
        pending.removeValue(forKey: "thumb")?.resume(returning: photo)
        await fulfillment(of: [loaded], timeout: 1)
        controller.endSession()
    }

    func testLeavingRangeReleasesAfterInjectedGrace() async {
        let started = expectation(description: "요청 시작")
        let graceStarted = expectation(description: "유예 시작")
        let cancelled = expectation(description: "소비자 취소")
        var pending: CheckedContinuation<UIImage, Error>?
        var release: CheckedContinuation<Void, Error>?
        var cancellationCount = 0
        let controller = ChatMediaViewportController(load: { _, _ in
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    pending = continuation
                    started.fulfill()
                }
            } onCancel: {
                cancelled.fulfill()
            }
        }, delay: {
            try await withCheckedThrowingContinuation { continuation in
                release = continuation
                graceStarted.fulfill()
            }
        })
        controller.onChange = { _, _, state in if case .idle = state { cancellationCount += 1 } }
        controller.resume()
        update(controller, priority: .visible)
        await fulfillment(of: [started], timeout: 1)
        update(controller, priority: nil)
        await fulfillment(of: [graceStarted], timeout: 1)
        XCTAssertEqual(cancellationCount, 0)
        release?.resume()
        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertEqual(cancellationCount, 1)
        pending?.resume(returning: UIImage())
        controller.endSession()
    }

    func testPathChangeRejectsLateResponseAndSuspendCancelsConsumer() async {
        var pending: [String: CheckedContinuation<UIImage, Error>] = [:]
        let firstStarted = expectation(description: "첫 경로 요청")
        let secondStarted = expectation(description: "새 경로 요청")
        let cancelled = expectation(description: "취소 전달")
        cancelled.expectedFulfillmentCount = 2
        let controller = ChatMediaViewportController { path, _ in
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    pending[path] = continuation
                    if path == "thumb" { firstStarted.fulfill() } else { secondStarted.fulfill() }
                }
            } onCancel: {
                cancelled.fulfill()
            }
        }
        controller.resume()
        update(controller, priority: .visible)
        await fulfillment(of: [firstStarted], timeout: 1)
        update(controller, priority: .visible, path: "new")
        await fulfillment(of: [secondStarted], timeout: 1)
        controller.suspend()
        await fulfillment(of: [cancelled], timeout: 1)
        let stale = expectation(description: "취소된 결과는 표시하지 않음")
        stale.isInverted = true
        controller.onChange = { _, _, state in if case .image = state { stale.fulfill() } }
        pending.removeValue(forKey: "thumb")?.resume(returning: UIImage())
        pending.removeValue(forKey: "new")?.resume(returning: UIImage())
        controller.endSession()
        await fulfillment(of: [stale], timeout: 0.05)
    }
}

private actor ViewportImageGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var starts = 0
    func started() { starts += 1 }
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        let current = waiters
        waiters.removeAll()
        current.forEach { $0.resume() }
    }
}

private final class ViewportReleaseProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var joined = false
    private var promoted = false
    private var released = false
    func record(count: Int) -> (joined: Bool, promoted: Bool, released: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let didJoin = count == 2 && !joined
        let didPromote = count == 3 && !promoted
        let didRelease = promoted && count == 1 && !released
        joined = joined || didJoin
        promoted = promoted || didPromote
        released = released || didRelease
        return (didJoin, didPromote, didRelease)
    }
}
