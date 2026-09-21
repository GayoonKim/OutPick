import Foundation
import Testing
import UIKit
@testable import OutPick

@MainActor
struct AvatarImagePresentationStateTests {
    @Test func memoryImageIsAvailableBeforeAsyncLoaderAndCannotSurviveIdentityChange() async {
        let state = AvatarImagePresentationState(), loader = AvatarPresentationLoader()
        let cached = UIImage()
        state.configure(identity: AvatarImageIdentity(userID: "first", path: "photo"), initialImage: cached, loader: loader.load)
        #expect(state.image === cached)
        await wait { loader.calls == 1 }
        state.configure(identity: AvatarImageIdentity(userID: "second", path: "other"), loader: loader.load)
        #expect(state.image == nil)
        await wait { loader.calls == 2 }
        loader.finish(0, .success(cached))
        let fresh = UIImage()
        loader.finish(1, .success(fresh))
        await wait { state.status == .loaded }
        #expect(state.image === fresh)
    }
    @Test func newMessageRetriesOnceButRepeatedRenderDoesNot() async {
        let state = AvatarImagePresentationState(), loader = AvatarPresentationLoader()
        state.configure(identity: AvatarImageIdentity(userID: "user", path: "photo"), loader: loader.load)
        state.displayed(eventID: "first-message")
        await wait { loader.calls == 1 }
        loader.finish(0, .failure(URLError(.timedOut)))
        await wait { state.status == .failed(retryable: true) }
        state.displayed(eventID: "first-message")
        #expect(loader.calls == 1)
        state.displayed(eventID: "new-message")
        await wait { loader.calls == 2 }
        loader.finish(1, .failure(URLError(.timedOut)))
        await wait { state.status == .failed(retryable: true) }
        state.displayed(eventID: "first-message")
        state.displayed(eventID: "new-message")
        #expect(loader.calls == 2)
    }

    @Test func explicitRefreshAllowsUnavailableFailureToRetry() async {
        let state = AvatarImagePresentationState(), loader = AvatarPresentationLoader()
        state.configure(identity: AvatarImageIdentity(userID: "user", path: "photo"), loader: loader.load)
        await wait { loader.calls == 1 }
        loader.finish(0, .failure(AvatarImageLoadingError.unavailable))
        await wait { state.status == .failed(retryable: false) }
        state.displayed(eventID: "new-message")
        #expect(loader.calls == 1)
        state.refreshFailure()
        await wait { loader.calls == 2 }
        loader.finish(1, .success(UIImage()))
        await wait { state.status == .loaded }
    }
    @Test func sameIdentityKeepsRequestAndLoadedImage() async {
        let state = AvatarImagePresentationState(), loader = AvatarPresentationLoader()
        let identity = AvatarImageIdentity(userID: "user", path: "photo")
        state.configure(identity: identity, loader: loader.load)
        await wait { loader.calls == 1 }
        state.configure(identity: identity, loader: loader.load)
        #expect(loader.calls == 1)
        let image = UIImage()
        loader.finish(0, .success(image))
        await wait { state.status == .loaded }
        state.configure(identity: identity, loader: loader.load)
        state.resume()
        #expect(state.image === image)
        #expect(loader.calls == 1)
    }

    @Test(arguments: [false, true]) func lateSuccessOrFailureCannotOverwriteAnotherUser(fails: Bool) async {
        let state = AvatarImagePresentationState(), loader = AvatarPresentationLoader()
        state.configure(identity: AvatarImageIdentity(userID: "old", path: "same"), loader: loader.load)
        await wait { loader.calls == 1 }
        state.configure(identity: AvatarImageIdentity(userID: "new", path: "same"), loader: loader.load)
        #expect(state.image == nil)
        await wait { loader.calls == 2 }
        let fresh = UIImage()
        loader.finish(1, .success(fresh))
        await wait { state.status == .loaded }
        loader.finish(0, fails ? .failure(URLError(.timedOut)) : .success(UIImage()))
        for _ in 0..<20 { await Task.yield() }
        #expect(state.image === fresh)
        #expect(state.status == .loaded)
    }

    @Test func removalAndSelectionPreventOldPhotoReturning() async {
        let state = AvatarImagePresentationState(), loader = AvatarPresentationLoader()
        state.configure(identity: AvatarImageIdentity(userID: "user", path: "old"), loader: loader.load)
        await wait { loader.calls == 1 }
        state.reset()
        loader.finish(0, .success(UIImage()))
        for _ in 0..<20 { await Task.yield() }
        #expect(state.image == nil)
        #expect(state.status == .idle)
        #expect(state.identity == nil)
    }

    @Test func transientFailureRetriesOnlyOnNewDisplayEvent() async {
        let state = AvatarImagePresentationState(), loader = AvatarPresentationLoader()
        let identity = AvatarImageIdentity(userID: "user", path: "photo")
        state.configure(identity: identity, loader: loader.load)
        await wait { loader.calls == 1 }
        loader.finish(0, .failure(URLError(.notConnectedToInternet)))
        await wait { state.status == .failed(retryable: true) }
        state.configure(identity: identity, loader: loader.load)
        for _ in 0..<20 { await Task.yield() }
        #expect(loader.calls == 1)
        state.resume()
        await wait { loader.calls == 2 }
        loader.finish(1, .success(UIImage()))
        await wait { state.status == .loaded }
    }

    @Test func unavailablePhotoWaitsForPathChange() async {
        let state = AvatarImagePresentationState(), loader = AvatarPresentationLoader()
        state.configure(identity: AvatarImageIdentity(userID: "user", path: "missing"), loader: loader.load)
        await wait { loader.calls == 1 }
        loader.finish(0, .failure(AvatarImageLoadingError.unavailable))
        await wait { state.status == .failed(retryable: false) }
        state.suspend(); state.resume()
        #expect(loader.calls == 1)
        state.configure(identity: AvatarImageIdentity(userID: "user", path: "new"), loader: loader.load)
        await wait { loader.calls == 2 }
        loader.finish(1, .success(UIImage()))
        await wait { state.status == .loaded }
    }

    @Test func cancelledCompletionCannotClearReplacementTask() async {
        let state = AvatarImagePresentationState(), loader = AvatarPresentationLoader()
        let identity = AvatarImageIdentity(userID: "user", path: "photo")
        state.configure(identity: identity, loader: loader.load)
        await wait { loader.calls == 1 }
        state.suspend()
        #expect(state.status == .idle)
        state.resume()
        await wait { loader.calls == 2 }
        loader.finish(0, .failure(URLError(.timedOut)))
        for _ in 0..<20 { await Task.yield() }
        #expect(state.status == .loading)
        state.configure(identity: identity, loader: loader.load)
        #expect(loader.calls == 2)
        loader.finish(1, .success(UIImage()))
        await wait { state.status == .loaded }
    }

    @Test func loadedImageSurvivesTemporaryDisappearance() async {
        let state = AvatarImagePresentationState(), loader = AvatarPresentationLoader()
        state.configure(identity: AvatarImageIdentity(userID: "user", path: "photo"), loader: loader.load)
        await wait { loader.calls == 1 }
        let image = UIImage()
        loader.finish(0, .success(image))
        await wait { state.status == .loaded }
        state.suspend(); state.resume()
        #expect(state.image === image)
        #expect(loader.calls == 1)
    }

    private func wait(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { await Task.yield() }
        #expect(condition())
    }
}

@MainActor
private final class AvatarPresentationLoader {
    var calls = 0
    private var pending: [Int: CheckedContinuation<UIImage?, Error>] = [:]
    func load() async throws -> UIImage? {
        let index = calls
        calls += 1
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func finish(_ index: Int, _ result: Result<UIImage?, Error>) {
        pending.removeValue(forKey: index)?.resume(with: result)
    }
}
