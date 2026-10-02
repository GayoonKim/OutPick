import Foundation
import Testing
@testable import OutPick

@MainActor
struct BlockedUsersViewModelTests {
    @Test func profilesLoadOnlyOnDemandAndFailureKeepsUnblockAvailable() async {
        let fixture = Fixture()
        await fixture.model.load()
        #expect(fixture.profiles.calls.isEmpty)
        await fixture.model.loadProfile(for: fixture.user)
        await fixture.model.loadProfile(for: fixture.user)
        #expect(fixture.profiles.calls == ["target"])
        #expect(fixture.model.state.nickname(for: fixture.user) == "저장된 이름")
        #expect(fixture.model.state.errorMessage == nil)
        await fixture.model.unblock(fixture.user)
        #expect(fixture.model.state.users.isEmpty)
    }

    @Test func latestProfileReplacesSnapshotAndSuppliesAvatar() async {
        let fixture = Fixture()
        fixture.profiles.result = .success(profile())
        await fixture.model.load()
        await fixture.model.loadProfile(for: fixture.user)
        #expect(fixture.model.state.nickname(for: fixture.user) == "최신 이름")
        #expect(fixture.model.state.profiles["target"]?.avatarThumbPath == "avatars/target/thumb.jpg")
    }

    @Test func duplicateUnblockIsSuppressedAndFailureAllowsRetry() async {
        let fixture = Fixture()
        await fixture.model.load()
        fixture.unblock.deferred = true
        let task = Task { await fixture.model.unblock(fixture.user) }
        while fixture.unblock.pending == nil { await Task.yield() }
        await fixture.model.unblock(fixture.user)
        await fixture.model.load()
        #expect(fixture.unblock.calls == 1)
        #expect(fixture.repository.loadCalls == 1)
        #expect(fixture.model.state.unblockingIDs == ["target"])
        fixture.unblock.pending?.resume(throwing: Failure.offline)
        fixture.unblock.pending = nil
        await task.value
        #expect(fixture.model.state.users.count == 1)
        #expect(fixture.model.state.unblockingIDs.isEmpty)
        #expect(fixture.model.state.errorMessage != nil)
        fixture.unblock.deferred = false
        await fixture.model.unblock(fixture.user)
        #expect(fixture.unblock.calls == 2)
        #expect(fixture.model.state.users.isEmpty)
        #expect(fixture.model.state.errorMessage == nil)
    }

    @Test func lateProfileDoesNotRestoreUnblockedUser() async {
        let fixture = Fixture()
        await fixture.model.load()
        fixture.profiles.deferred = true
        let task = Task { await fixture.model.loadProfile(for: fixture.user) }
        while fixture.profiles.pending == nil { await Task.yield() }
        await fixture.model.unblock(fixture.user)
        fixture.profiles.pending?.resume(returning: profile())
        fixture.profiles.pending = nil
        await task.value
        #expect(fixture.model.state.users.isEmpty)
        #expect(fixture.model.state.profiles.isEmpty)
    }

    @Test func refreshRejectsOldProfileResponseAndRetriesFailedProfile() async {
        let fixture = Fixture()
        await fixture.model.load()
        fixture.profiles.deferred = true
        let task = Task { await fixture.model.loadProfile(for: fixture.user) }
        while fixture.profiles.pending == nil { await Task.yield() }
        await fixture.model.load()
        fixture.profiles.pending?.resume(returning: profile())
        fixture.profiles.pending = nil
        await task.value
        #expect(fixture.model.state.profiles.isEmpty)
        fixture.profiles.deferred = false
        await fixture.model.loadProfile(for: fixture.user)
        #expect(fixture.profiles.calls.count == 2)
    }

    @Test func listFailureEndsLoadingAndRetryRestoresList() async {
        let fixture = Fixture()
        fixture.repository.fails = true
        await fixture.model.load()
        #expect(!fixture.model.state.isLoading)
        #expect(!fixture.model.state.hasLoaded)
        #expect(fixture.model.state.errorMessage != nil)
        fixture.repository.fails = false
        await fixture.model.load()
        #expect(fixture.model.state.hasLoaded)
        #expect(fixture.model.state.users.count == 1)
        #expect(fixture.model.state.errorMessage == nil)
    }

    private func profile() -> UserPublicProfile {
        UserPublicProfile(userID: "target", nickname: "최신 이름",
                          avatarThumbPath: "avatars/target/thumb.jpg")
    }
}

private enum Failure: Error { case offline }

@MainActor
private final class Fixture {
    let user = UserBlock(blockerUserID: UserID(value: "me"), blockedUserID: UserID(value: "target"),
                         blockedUserNicknameSnapshot: "저장된 이름", source: .chat, createdAt: Date())
    let repository = BlockRepository()
    let profiles = ProfileRepository()
    let unblock = UnblockUseCase()
    lazy var model = BlockedUsersViewModel(currentUserID: "me", repository: repository,
        unblockUserUseCase: unblock, profileRepository: profiles)
    init() { repository.users = [user] }
}

private final class BlockRepository: UserBlockRepositoryProtocol {
    var users: [UserBlock] = []
    var fails = false
    var loadCalls = 0
    func fetchBlockedUsers(blockerUserID: UserID) async throws -> [UserBlock] {
        loadCalls += 1
        if fails { throw Failure.offline }
        return users
    }
    func blockUser(blockerUserID: UserID, blockedUserID: UserID,
                   blockedUserNicknameSnapshot: String?, source: UserBlockSource) async throws -> UserBlock {
        throw Failure.offline
    }
    func unblockUser(blockerUserID: UserID, blockedUserID: UserID) async throws { }
    func fetchBlockedUserIDs(blockerUserID: UserID) async throws -> Set<UserID> { [] }
    func fetchHiddenCommentUserIDs(currentUserID: UserID) async throws -> Set<UserID> { [] }
}

private final class ProfileRepository: UserPublicProfileRepositoryProtocol {
    var result: Result<UserPublicProfile, Error> = .failure(Failure.offline)
    var calls: [String] = []
    var deferred = false
    var pending: CheckedContinuation<UserPublicProfile, Error>?
    func fetchProfile(userID: String) async throws -> UserPublicProfile {
        calls.append(userID)
        if deferred { return try await withCheckedThrowingContinuation { pending = $0 } }
        return try result.get()
    }
    func fetchProfiles(userIDs: [String]) async throws -> [String: UserPublicProfile] { [:] }
}

private final class UnblockUseCase: UnblockUserUseCaseProtocol {
    var deferred = false
    var calls = 0
    var pending: CheckedContinuation<Void, Error>?
    func execute(blockerUserID: UserID, blockedUserID: UserID) async throws {
        calls += 1
        if deferred { try await withCheckedThrowingContinuation { pending = $0 } }
    }
}
