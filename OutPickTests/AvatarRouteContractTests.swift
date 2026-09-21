import XCTest
import UIKit
@testable import OutPick

@MainActor
final class AvatarRouteContractTests: XCTestCase {
    func testDetailFactoryPreservesCallerCachePolicy() async throws {
        for policy in [AvatarImageCachePolicy.memoryOnly, .memoryAndDisk] {
            let spy = AvatarRouteImageSpy()
            let manager = spy.scoped { policy }
            let profile = UserPublicProfile(userID: "other", nickname: "프로필", avatarThumbPath: "thumb", avatarOriginalPath: "original")
            let detail = UserProfileDetailCompositionRoot.makeDetail(
                userID: "other", seedNickname: "프로필", seedAvatarPath: "thumb",
                avatarImageManager: manager, currentUserProvider: AvatarRouteCurrentUser(),
                publicProfileRepository: AvatarRouteProfileRepository(profile: profile),
                photoLibrarySaver: AvatarRouteSaver(), onBack: {}
            )
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = detail
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            await waitUntil { !spy.requests.isEmpty }
            // UIWindow의 첫 appearance 전환이 끝난 뒤 테스트 창을 정리한다.
            try await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertTrue(spy.requests.allSatisfy { $0.path == "thumb" && $0.representation == .thumbnail && $0.cachePolicy == policy })
            XCTAssertTrue(spy.originalPaths.isEmpty)
        }
    }

    func testExistingScopeRechecksMembershipForReadLoadAndPrefetch() async throws {
        let spy = AvatarRouteImageSpy()
        var joined = false
        let manager = spy.scoped { joined ? .memoryAndDisk : .memoryOnly }
        for value in [false, true, false] {
            joined = value
            let expected: AvatarImageCachePolicy = value ? .memoryAndDisk : .memoryOnly
            XCTAssertEqual(manager.avatarCachePolicy, expected)
            _ = await manager.cachedAvatar(for: "read")
            _ = try await manager.loadAvatar(for: "load", maxBytes: 1)
            await manager.prefetchAvatars(paths: ["prefetch"], maxBytes: 1, maxConcurrent: 1)
            XCTAssertEqual(spy.reads.last?.cachePolicy, expected)
            XCTAssertTrue(spy.requests.suffix(2).allSatisfy { $0.cachePolicy == expected && $0.representation == .thumbnail })
        }
        _ = try await manager.loadOriginalAvatar(for: "original")
        XCTAssertEqual(spy.originalPaths, ["original"])
    }

    func testOriginalOnlyProfileUsesOriginalLoaderForDetailAndRepeatedViewer() async throws {
        let spy = AvatarRouteImageSpy()
        let profile = UserPublicProfile(userID: "legacy", nickname: "원본만 있는 프로필", avatarThumbPath: nil, avatarOriginalPath: "legacy-original")
        let detail = UserProfileDetailCompositionRoot.makeDetail(
            userID: "legacy", seedNickname: "프로필", seedAvatarPath: nil,
            avatarImageManager: spy.scoped { .memoryAndDisk },
            currentUserProvider: AvatarRouteCurrentUser(),
            publicProfileRepository: AvatarRouteProfileRepository(profile: profile),
            photoLibrarySaver: AvatarRouteSaver(), onBack: {}
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = detail
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        await waitUntil { spy.originalPaths.count == 1 }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(spy.requests.isEmpty)
        for _ in 0..<2 {
            let previous = spy.originalPaths.count
            detail.perform(NSSelectorFromString("profileImageTapped"))
            await waitUntil { detail.presentedViewController is SimpleImageViewerVC && spy.originalPaths.count > previous }
            let viewer = try XCTUnwrap(detail.presentedViewController as? SimpleImageViewerVC)
            if let transition = viewer.transitionCoordinator {
                await withCheckedContinuation { continuation in
                    transition.animate(alongsideTransition: nil) { _ in continuation.resume() }
                }
            }
            await withCheckedContinuation { continuation in
                detail.dismiss(animated: false) { continuation.resume() }
            }
            XCTAssertNil(detail.presentedViewController)
        }
        XCTAssertTrue(spy.originalPaths.allSatisfy { $0 == "legacy-original" })
        XCTAssertTrue(spy.requests.isEmpty, "원본-only 사진이 썸네일 저장 경로로 넘어가면 안 됩니다.")
        XCTAssertTrue(spy.reads.isEmpty, "원본-only 확대가 썸네일 캐시를 조회하면 안 됩니다.")
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(condition())
    }
}

@MainActor
final class AvatarRouteImageSpy: AvatarImageManaging {
    var requests: [AvatarImageRequest] = []
    var reads: [AvatarImageRequest] = []
    var originalPaths: [String] = []
    let image = UIImage(systemName: "person.circle")!
    func cachedAvatar(_ request: AvatarImageRequest) async -> UIImage? { reads.append(request); return nil }
    func loadAvatar(_ request: AvatarImageRequest) async throws -> UIImage { requests.append(request); return image }
    func loadOriginalAvatar(for path: String) async throws -> UIImage { originalPaths.append(path); return image }
    func cachedAvatar(for path: String) async -> UIImage? { XCTFail("정책 없는 캐시 요청"); return nil }
    func loadAvatar(for path: String, maxBytes: Int) async throws -> UIImage { XCTFail("정책 없는 로드 요청"); return image }
    func prefetchAvatars(paths: [String], maxBytes: Int, maxConcurrent: Int) async { XCTFail("정책 없는 선로딩") }
    func storeAvatarDataToCache(_ data: Data, for path: String) async throws {}
    func removeCachedAvatar(for path: String) async {}
}

private struct AvatarRouteCurrentUser: CurrentUserProviding {
    let email = "qa@example.invalid"
    let canonicalUserID = "self"
    let nickname: String? = "현재 사용자"
    let avatarPath: String? = nil
    let profile: UserPublicProfile? = nil
}

private struct AvatarRouteProfileRepository: UserPublicProfileRepositoryProtocol {
    let profile: UserPublicProfile
    func fetchProfile(userID: String) async throws -> UserPublicProfile { profile }
    func fetchProfiles(userIDs: [String]) async throws -> [String: UserPublicProfile] { [profile.userID: profile] }
}

private struct AvatarRouteSaver: PhotoLibrarySaving {
    func saveImage(_ image: UIImage) async throws { XCTFail("QA에서 사진 저장을 호출하면 안 됩니다.") }
    func saveVideo(fileURL: URL) async throws { XCTFail("QA에서 영상 저장을 호출하면 안 됩니다.") }
}
