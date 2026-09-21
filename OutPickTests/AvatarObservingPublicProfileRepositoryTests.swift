import Foundation
import Testing
import UIKit
@testable import OutPick

struct AvatarObservingPublicProfileRepositoryTests {
    @Test func delayedFetchFromOldSessionIsRejected() async {
        let images = ObservingRepositoryImages()
        let base = ObservingRepositoryFake()
        let repository = AvatarObservingPublicProfileRepository(base: base, images: images)
        let fetch = Task { try await repository.fetchProfile(userID: "user") }
        await base.gate.waitUntilStarted()
        await images.transitionAvatarSession(to: "new")
        await base.gate.release()
        await #expect(throws: CancellationError.self) { try await fetch.value }
        #expect(await base.calls == 1)
    }

    @Test func batchMissingProfileIsNotTreatedAsPhotoRemoval() async throws {
        let images = ObservingRepositoryImages()
        let base = ObservingRepositoryFake()
        let repository = AvatarObservingPublicProfileRepository(base: base, images: images)
        let result = try await repository.fetchProfiles(userIDs: ["missing"])
        #expect(result.isEmpty)
        #expect(await images.observedCount == 0)
        #expect(await base.calls == 1)
    }
}

private actor ObservingRepositoryFake: UserPublicProfileRepositoryProtocol {
    let gate = AvatarTestGate()
    var calls = 0
    func fetchProfile(userID: String) async throws -> UserPublicProfile {
        calls += 1
        await gate.wait()
        return avatarTestProfile(thumb: "old", date: 1)
    }
    func fetchProfiles(userIDs: [String]) async throws -> [String: UserPublicProfile] {
        calls += 1
        return [:]
    }
}

private actor ObservingRepositoryImages: AvatarImageManaging {
    let session = AvatarImageSessionController()
    var observedCount = 0
    func transitionAvatarSession(to userID: String?) async { await session.transition(to: userID) {} }
    func avatarSessionToken() async -> UInt64? { await session.token() }
    func observeAvatarProfile(_ profile: UserPublicProfile, previous: UserPublicProfile?, token: UInt64?) async -> UserPublicProfile? {
        observedCount += 1
        return await session.observe(profile, previous: previous, token: token) { _ in }
    }
    func cachedAvatar(for path: String) async -> UIImage? { nil }
    func loadAvatar(for path: String, maxBytes: Int) async throws -> UIImage { throw URLError(.unknown) }
    func prefetchAvatars(paths: [String], maxBytes: Int, maxConcurrent: Int) async {}
    func storeAvatarDataToCache(_ data: Data, for path: String) async throws {}
    func removeCachedAvatar(for path: String) async {}
}
