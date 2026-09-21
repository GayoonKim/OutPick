import Foundation
import Testing
import UIKit
@testable import OutPick

struct AvatarImageSessionTests {
    @Test @MainActor func immediateReadIsBlockedThroughoutSessionClear() async {
        let session = AvatarImageSessionController(requiresSession: true)
        let image = UIImage()
        #expect(session.immediateReads.read(path: "photo") { image } == nil)
        await session.transition(to: "user") {}
        #expect(session.immediateReads.read(path: "photo") { image } === image)
        let gate = AvatarTestGate()
        let logout = Task { await session.transition(to: nil) { await gate.wait() } }
        await gate.waitUntilStarted()
        #expect(session.immediateReads.read(path: "photo") { image } == nil)
        await gate.release()
        await logout.value
        #expect(session.immediateReads.read(path: "photo") { image } == nil)
    }

    @Test @MainActor func immediateReadCannotRestoreRetiredPhotoDuringInvalidation() async {
        let session = AvatarImageSessionController()
        let image = UIImage(), token = await session.token()
        _ = await session.observe(avatarTestProfile(thumb: "old", date: 1), previous: nil, token: token) { _ in }
        let gate = AvatarTestGate()
        let removal = Task {
            await session.observe(avatarTestProfile(thumb: "new", date: 2), previous: nil, token: token) { path in
                if path == "old" { await gate.wait() }
            }
        }
        await gate.waitUntilStarted()
        #expect(session.immediateReads.read(path: "old") { image } == nil)
        #expect(session.immediateReads.read(path: "new") { image } === image)
        await gate.release()
        _ = await removal.value
        #expect(session.immediateReads.read(path: "old") { image } == nil)
        await session.markUnavailable(path: "new", token: token)
        #expect(session.immediateReads.read(path: "new") { image } == nil)
        await session.resetFailures(paths: ["new"])
        #expect(session.immediateReads.read(path: "new") { image } === image)
    }
    @Test func undatedSnapshotCannotResurrectRemovedPhoto() async {
        let session = AvatarImageSessionController()
        let token = await session.token()
        var old = avatarTestProfile(thumb: "old", date: 1)
        old.updatedAt = nil
        var removed = avatarTestProfile(thumb: nil, date: 2)
        removed.updatedAt = nil
        _ = await session.observe(old, previous: nil, token: token) { _ in }
        _ = await session.observe(removed, previous: nil, token: token) { _ in }
        #expect(await session.observe(old, previous: nil, token: token) { _ in } == removed)
    }
    @Test(arguments: [false, true]) func lateSuccessAndFailureBecomeCancellation(fails: Bool) async throws {
        let session = AvatarImageSessionController()
        let gate = AvatarTestGate()
        let work = Task {
            try await session.perform(path: "old") {
                await gate.wait()
                if fails { throw URLError(.networkConnectionLost) }
                return UIImage()
            }
        }
        await gate.waitUntilStarted()
        await session.transition(to: "new") {}
        await gate.release()
        await #expect(throws: CancellationError.self) { try await work.value }
    }

    @Test func transitionsSerializeClearsAndBlockAdmission() async throws {
        let session = AvatarImageSessionController()
        let gate = AvatarTestGate()
        let first = Task { await session.transition(to: nil) { await gate.wait() } }
        await gate.waitUntilStarted()
        #expect(await session.token() == nil)
        await #expect(throws: CancellationError.self) { try await session.perform(path: "blocked") { UIImage() } }
        let second = Task { await session.transition(to: "next") {} }
        first.cancel()
        await gate.release()
        await first.value
        await second.value
        #expect(await session.token() != nil)
        #expect(try await session.perform(path: "next") { UIImage() } != nil)
    }

    @Test func removalCancelsActiveRequestAndOldMetadataCannotRestoreIt() async throws {
        let session = AvatarImageSessionController()
        let token = await session.token()
        _ = await session.observe(avatarTestProfile(thumb: "old", date: 1), previous: nil, token: token) { _ in }
        let gate = AvatarTestGate()
        let work = Task { try await session.perform(path: "old") { await gate.wait(); return UIImage() } }
        await gate.waitUntilStarted()
        let removed = avatarTestProfile(thumb: nil, date: 2)
        _ = await session.observe(removed, previous: nil, token: token) { _ in }
        await gate.release()
        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(await session.observe(avatarTestProfile(thumb: "old", date: 1), previous: nil, token: token) { _ in } == removed)
    }

    @Test func oldSessionMetadataCannotInvalidateNewSession() async {
        let session = AvatarImageSessionController()
        let oldToken = await session.token()
        await session.transition(to: "next") {}
        #expect(await session.observe(avatarTestProfile(thumb: nil, date: 3), previous: nil, token: oldToken) { _ in Issue.record("이전 세션이 무효화했습니다.") } == nil)
    }

    @Test func sameAccountRelaunchRetainsDiskButLogoutClearsIt() async throws {
        let suite = "AvatarSession-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AvatarImageSessionController(requiresSession: true, ownerDefaults: defaults)
        await first.transition(to: "user") {}
        let relaunched = AvatarImageSessionController(requiresSession: true, ownerDefaults: defaults)
        await relaunched.transition(to: "user") { Issue.record("같은 계정 앱 재실행에서 디스크를 지우면 안 됩니다.") }
        let cleared = AvatarTestGate()
        await relaunched.transition(to: nil) { await cleared.release() }
        #expect(await cleared.isReleased)
    }
}

actor AvatarTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false
    private(set) var isReleased = false
    func wait() async {
        started = true
        guard !isReleased else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilStarted() async {
        let deadline = Date().addingTimeInterval(3)
        while !started, Date() < deadline { await Task.yield() }
        #expect(started)
    }
    func release() { isReleased = true; continuation?.resume(); continuation = nil }
}
