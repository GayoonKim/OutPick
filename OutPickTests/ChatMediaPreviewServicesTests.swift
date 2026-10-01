import Foundation
import Testing
@testable import OutPick

@MainActor
struct ChatMediaPreviewServicesTests {
    private func resource(expiry: Date) -> ChatVideoPlaybackResource {
        ChatVideoPlaybackResource(roomID: "room", messageID: "message", attachmentID: "attachment",
            path: "gs://ready/rooms/room/messages/message/attachments/attachment/display",
            generation: "123", mediaExpiresAt: expiry)!
    }

    @Test func streamsWithoutFullDownloadAndSavingCarriesOriginalExpiry() async throws {
        let current = Date()
        let resource = resource(expiry: current.addingTimeInterval(600))
        let repository = PlaybackRepositorySpy(now: { current })
        let files = VideoOriginalFilesSpy()
        let resolver = DefaultChatVideoPlaybackResolver(repository: repository, originalFiles: files, now: { current })
        let first = try await resolver.playbackAsset(for: resource)
        let second = try await resolver.playbackAsset(for: resource)
        #expect(repository.calls == 1)
        #expect(first == second)
        #expect(files.acquiredResources.isEmpty)
        let saved = try await resolver.acquireFileForSaving(first)
        #expect(files.acquiredResources == [resource.original])
        await saved.release()
    }

    @Test func cachedOriginalStartsWithNoURLRequest() async throws {
        let resource = resource(expiry: Date().addingTimeInterval(600))
        let repository = PlaybackRepositorySpy()
        let files = VideoOriginalFilesSpy()
        files.hasCached = true
        let resolver = DefaultChatVideoPlaybackResolver(repository: repository, originalFiles: files)
        let asset = try await resolver.playbackAsset(for: resource)
        #expect(asset.url == files.url)
        #expect(asset.resource == resource)
        #expect(repository.calls == 0)
        await asset.fileLease?.release()
    }

    @Test func concurrentRequestsShareIssuance() async throws {
        let resource = resource(expiry: Date().addingTimeInterval(600))
        let repository = PlaybackRepositorySpy()
        repository.delayed = true
        let resolver = DefaultChatVideoPlaybackResolver(repository: repository, originalFiles: VideoOriginalFilesSpy())
        let first = Task { try await resolver.playbackAsset(for: resource) }
        let second = Task { try await resolver.playbackAsset(for: resource) }
        for _ in 0..<100 where repository.pending == nil { await Task.yield() }
        #expect(repository.calls == 1)
        repository.finish()
        _ = try await first.value
        _ = try await second.value
        #expect(repository.calls == 1)
    }

    @Test func responseArrivingAfterMediaExpiryIsDiscarded() async throws {
        var current = Date()
        let resource = resource(expiry: current.addingTimeInterval(10))
        let repository = PlaybackRepositorySpy(now: { current })
        repository.delayed = true
        let resolver = DefaultChatVideoPlaybackResolver(repository: repository, originalFiles: VideoOriginalFilesSpy(), now: { current })
        let task = Task { try await resolver.playbackAsset(for: resource) }
        for _ in 0..<100 where repository.pending == nil { await Task.yield() }
        current = resource.mediaExpiresAt
        repository.finish()
        do { _ = try await task.value; Issue.record("만료 뒤 URL을 반환함") }
        catch { #expect(error as? ChatVideoPlaybackError == .expired) }
    }

    @Test func accountInvalidationDiscardsLateResponse() async throws {
        let resource = resource(expiry: Date().addingTimeInterval(600))
        let repository = PlaybackRepositorySpy()
        repository.delayed = true
        let resolver = DefaultChatVideoPlaybackResolver(repository: repository, originalFiles: VideoOriginalFilesSpy())
        let task = Task { try await resolver.playbackAsset(for: resource) }
        for _ in 0..<100 where repository.pending == nil { await Task.yield() }
        resolver.invalidateSession()
        repository.finish()
        do { _ = try await task.value; Issue.record("종료된 계정 세션에 URL을 반환함") }
        catch { #expect(error is CancellationError) }
        #expect(!resolver.isSessionValid)
    }

    @Test func renewalDoesNotExtendMediaExpiryAndDeletionBlocksCachedURL() async throws {
        var current = Date()
        let resource = resource(expiry: current.addingTimeInterval(600))
        let repository = PlaybackRepositorySpy(now: { current })
        let resolver = DefaultChatVideoPlaybackResolver(repository: repository, originalFiles: VideoOriginalFilesSpy(), now: { current })
        let first = try await resolver.playbackAsset(for: resource)
        current = try #require(first.urlExpiresAt)
        let renewed = try await resolver.playbackAsset(for: resource)
        #expect(repository.calls == 2)
        #expect(renewed.resource?.mediaExpiresAt == resource.mediaExpiresAt)
        await resolver.removeCachedURL(for: resource.path)
        do { _ = try await resolver.playbackAsset(for: resource); Issue.record("삭제 뒤 URL을 재사용함") }
        catch { #expect(error as? ChatVideoPlaybackError == .unavailable) }
    }

    @Test func pathOnlyEntryAcceptsOnlyLocalOutboxFiles() async throws {
        let repository = PlaybackRepositorySpy()
        let resolver = DefaultChatVideoPlaybackResolver(repository: repository, originalFiles: VideoOriginalFilesSpy())
        let local = try await resolver.playbackAsset(forPath: "/tmp/outbox.mp4")
        #expect(local.url.isFileURL)
        do { _ = try await resolver.playbackAsset(forPath: "gs://ready/video"); Issue.record("원격 path-only 재생 허용") }
        catch { #expect(error as? ChatVideoPlaybackError == .unavailable) }
        #expect(repository.calls == 0)
    }

    @Test func callableSendsOnlyIdentifiersAndRejectsExtendedExpiry() async throws {
        let expiry = Date(timeIntervalSince1970: 2_000_000_000)
        let resource = resource(expiry: expiry)
        let transport = PlaybackTransportSpy()
        transport.response = ["url": "https://example.com/video?signature=fixture",
                              "urlExpiresAt": expiry.addingTimeInterval(-10).timeIntervalSince1970 * 1000,
                              "mediaExpiresAt": expiry.timeIntervalSince1970 * 1000]
        let repository = CloudFunctionsChatVideoPlaybackURLRepository(transport: transport)
        _ = try await repository.issue(for: resource)
        #expect(transport.name == "issueChatVideoPlaybackURL")
        #expect(Set(transport.data.keys) == ["roomID", "messageID", "attachmentID"])
        transport.response["mediaExpiresAt"] = expiry.addingTimeInterval(1).timeIntervalSince1970 * 1000
        do { _ = try await repository.issue(for: resource); Issue.record("서버 기한 변경 허용") }
        catch { #expect(error as? ChatVideoPlaybackError == .invalidResponse) }
    }
}

@MainActor
private final class PlaybackRepositorySpy: ChatVideoPlaybackURLRepository {
    var calls = 0
    var delayed = false
    var pending: CheckedContinuation<Void, Never>?
    let now: () -> Date
    init(now: @escaping () -> Date = Date.init) { self.now = now }
    func issue(for resource: ChatVideoPlaybackResource) async throws -> ChatVideoPlaybackURL {
        calls += 1
        let expiry = min(now().addingTimeInterval(60), resource.mediaExpiresAt)
        if delayed { await withCheckedContinuation { pending = $0 } }
        return ChatVideoPlaybackURL(url: URL(string: "https://example.com/video")!,
            urlExpiresAt: expiry, mediaExpiresAt: resource.mediaExpiresAt)
    }
    func finish() { let saved = pending; pending = nil; saved?.resume() }
}

private final class VideoOriginalFilesSpy: ChatOriginalFileLoading {
    let url = URL(fileURLWithPath: "/tmp/original-test.mp4")
    var acquiredResources: [ChatOriginalResource] = []
    var hasCached = false
    func acquireOriginal(_ resource: ChatOriginalResource, purpose: ChatOriginalPurpose) async throws -> ChatOriginalFileLease {
        acquiredResources.append(resource)
        return ChatOriginalFileLease(fileURL: url, isValid: { true }, release: {})
    }
    func cachedOriginal(_ resource: ChatOriginalResource) async throws -> ChatOriginalFileLease? {
        hasCached ? ChatOriginalFileLease(fileURL: url, isValid: { true }, release: {}) : nil
    }
    func removeOriginal(path: String) async {}
    func removeExpiredOriginals(at now: Date) async -> Bool { true }
    func invalidateSession() {}
}

private final class PlaybackTransportSpy: CloudFunctionsTransporting {
    var response: [String: Any] = [:]
    var name = ""
    var data: [String: Any] = [:]
    func call(_ name: String, data: [String: Any]) async throws -> [String: Any] {
        self.name = name
        self.data = data
        return response
    }
}
