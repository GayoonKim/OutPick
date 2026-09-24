//
//  ChatMediaPreviewServicesTests.swift
//  OutPickTests
//
//  Created by Codex on 6/19/26.
//

import Foundation
import Testing
@testable import OutPick

struct ChatMediaPreviewServicesTests {
    @Test func scopedPlaybackStreamsWithoutStartingFullDownloadAndSaveUsesLease() async throws {
        let remote = URL(string: "https://example.com/original.mp4")!
        let files = VideoOriginalFilesSpy()
        let legacy = ChatVideoDiskCacheSpy()
        let downloader = ChatRemoteFileDownloaderSpy()
        let resolver = DefaultChatVideoPlaybackResolver(
            storageURLResolver: ChatStorageURLResolverSpy(resolvedURLs: ["rooms/a.mp4": remote]),
            videoDiskCache: legacy, fileDownloader: downloader, originalFiles: files
        )
        let asset = try await resolver.playbackAsset(forPath: "rooms/a.mp4")
        #expect(asset.url == remote)
        #expect(files.acquiredPaths.isEmpty)
        #expect(legacy.cacheCalls.isEmpty)
        #expect(legacy.existsKeys.isEmpty)
        #expect(downloader.downloadedURLs.isEmpty)
        let saved = try await resolver.acquireFileForSaving(asset)
        #expect(files.acquiredPaths == ["rooms/a.mp4"])
        #expect(saved.fileURL == files.url)
        await saved.release()
    }

    @Test func scopedPlaybackReusesPinnedOriginalWithoutURLResolution() async throws {
        let files = VideoOriginalFilesSpy()
        files.hasCached = true
        let urls = ChatStorageURLResolverSpy()
        let resolver = DefaultChatVideoPlaybackResolver(
            storageURLResolver: urls, videoDiskCache: ChatVideoDiskCacheSpy(),
            fileDownloader: ChatRemoteFileDownloaderSpy(), originalFiles: files
        )
        let asset = try await resolver.playbackAsset(forPath: "rooms/a.mp4")
        #expect(asset.url == files.url)
        #expect(asset.fileLease?.isValid == true)
        #expect(urls.requestedPaths.isEmpty)
        await asset.fileLease?.release()
    }

    @Test func playbackAssetUsesLocalFilePathWithoutStorageLookup() async throws {
        let storageResolver = ChatStorageURLResolverSpy()
        let videoCache = ChatVideoDiskCacheSpy()
        let resolver = makeResolver(storageResolver: storageResolver, videoCache: videoCache)
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        let asset = try await resolver.playbackAsset(forPath: localURL.path)

        #expect(asset.url == localURL)
        #expect(asset.storagePath == nil)
        #expect(storageResolver.requestedPaths.isEmpty)
        #expect(videoCache.existsKeys.isEmpty)
    }

    @Test func playbackAssetUsesCachedVideoBeforeRemoteURL() async throws {
        let storageResolver = ChatStorageURLResolverSpy()
        let cachedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cached-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        let videoCache = ChatVideoDiskCacheSpy(existingURLs: ["rooms/1/video.mp4": cachedURL])
        let resolver = makeResolver(storageResolver: storageResolver, videoCache: videoCache)

        let asset = try await resolver.playbackAsset(forPath: "rooms/1/video.mp4")

        #expect(asset.url == cachedURL)
        #expect(asset.storagePath == "rooms/1/video.mp4")
        #expect(videoCache.existsKeys == ["rooms/1/video.mp4"])
        #expect(storageResolver.requestedPaths.isEmpty)
    }

    @Test func playbackAssetResolvesRemoteStoragePathWhenCacheMisses() async throws {
        let remoteURL = try #require(URL(string: "https://example.com/video.mp4"))
        let storageResolver = ChatStorageURLResolverSpy(resolvedURLs: ["rooms/1/video.mp4": remoteURL])
        let videoCache = ChatVideoDiskCacheSpy()
        let resolver = makeResolver(storageResolver: storageResolver, videoCache: videoCache)

        let asset = try await resolver.playbackAsset(forPath: "rooms/1/video.mp4")

        #expect(asset.url == remoteURL)
        #expect(asset.storagePath == "rooms/1/video.mp4")
        #expect(storageResolver.requestedPaths == ["rooms/1/video.mp4"])
    }

    @Test func localFileURLForSavingUsesCachedStorageFile() async throws {
        let cachedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cached-save-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        let videoCache = ChatVideoDiskCacheSpy(existingURLs: ["rooms/1/video.mp4": cachedURL])
        let downloader = ChatRemoteFileDownloaderSpy()
        let resolver = makeResolver(videoCache: videoCache, downloader: downloader)
        var progressValues: [Double] = []

        let fileURL = try await resolver.localFileURLForSaving(
            localURL: nil,
            storagePath: "rooms/1/video.mp4",
            onProgress: { progressValues.append($0) }
        )

        #expect(fileURL == cachedURL)
        #expect(progressValues == [1.0])
        #expect(downloader.downloadedURLs.isEmpty)
    }

    @Test func localFileURLForSavingDownloadsRemoteURLWhenNoCacheExists() async throws {
        let remoteURL = try #require(URL(string: "https://example.com/video.mp4"))
        let downloadedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("downloaded-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        let storageResolver = ChatStorageURLResolverSpy(resolvedURLs: ["rooms/1/video.mp4": remoteURL])
        let downloader = ChatRemoteFileDownloaderSpy(downloadedURL: downloadedURL)
        let resolver = makeResolver(storageResolver: storageResolver, downloader: downloader)
        var progressValues: [Double] = []

        let fileURL = try await resolver.localFileURLForSaving(
            localURL: nil,
            storagePath: "rooms/1/video.mp4",
            onProgress: { progressValues.append($0) }
        )

        #expect(fileURL == downloadedURL)
        #expect(storageResolver.requestedPaths == ["rooms/1/video.mp4"])
        #expect(downloader.downloadedURLs == [remoteURL])
        #expect(progressValues == [1.0])
    }

    @Test func localFileURLForSavingThrowsWhenSourceIsMissing() async throws {
        let resolver = makeResolver()

        do {
            _ = try await resolver.localFileURLForSaving(localURL: nil, storagePath: nil, onProgress: { _ in })
            Issue.record("Expected missingSaveSource error")
        } catch let error as ChatMediaPreviewError {
            #expect(error == .missingSaveSource)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeResolver(
        storageResolver: ChatStorageURLResolverSpy = ChatStorageURLResolverSpy(),
        videoCache: ChatVideoDiskCacheSpy = ChatVideoDiskCacheSpy(),
        downloader: ChatRemoteFileDownloaderSpy = ChatRemoteFileDownloaderSpy()
    ) -> DefaultChatVideoPlaybackResolver {
        DefaultChatVideoPlaybackResolver(
            storageURLResolver: storageResolver,
            videoDiskCache: videoCache,
            fileDownloader: downloader
        )
    }
}

private final class VideoOriginalFilesSpy: ChatOriginalFileLoading {
    let url = URL(fileURLWithPath: "/tmp/original-test.mp4")
    var acquiredPaths: [String] = []
    var hasCached = false
    func acquireOriginal(_ resource: ChatOriginalResource, purpose: ChatOriginalPurpose) async throws -> ChatOriginalFileLease {
        acquiredPaths.append(resource.path)
        return ChatOriginalFileLease(fileURL: url, isValid: { true }, release: {})
    }
    func cachedOriginal(_ resource: ChatOriginalResource) async throws -> ChatOriginalFileLease? {
        hasCached ? ChatOriginalFileLease(fileURL: url, isValid: { true }, release: {}) : nil
    }
    func removeOriginal(path: String) async {}
    func invalidateSession() {}
}

private final class ChatStorageURLResolverSpy: ChatStorageURLResolving {
    var resolvedURLs: [String: URL]
    private(set) var requestedPaths: [String] = []

    init(resolvedURLs: [String: URL] = [:]) {
        self.resolvedURLs = resolvedURLs
    }

    func url(for path: String) async throws -> URL {
        requestedPaths.append(path)
        if let url = resolvedURLs[path] {
            return url
        }
        throw URLError(.badURL)
    }
}

private final class ChatVideoDiskCacheSpy: ChatVideoDiskCaching {
    var existingURLs: [String: URL]
    private(set) var existsKeys: [String] = []
    private(set) var cacheCalls: [(remote: URL, key: String)] = []

    init(existingURLs: [String: URL] = [:]) {
        self.existingURLs = existingURLs
    }

    func exists(forKey key: String) async -> URL? {
        existsKeys.append(key)
        return existingURLs[key]
    }

    func cache(from remote: URL, key: String) async throws -> URL {
        cacheCalls.append((remote, key))
        return existingURLs[key] ?? remote
    }
}

private final class ChatRemoteFileDownloaderSpy: ChatRemoteFileDownloading {
    let downloadedURL: URL
    private(set) var downloadedURLs: [URL] = []

    init(downloadedURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent("downloaded.mp4")) {
        self.downloadedURL = downloadedURL
    }

    func downloadToTemporaryFile(from remote: URL, onProgress: @escaping (Double) -> Void) async throws -> URL {
        downloadedURLs.append(remote)
        onProgress(1.0)
        return downloadedURL
    }
}
