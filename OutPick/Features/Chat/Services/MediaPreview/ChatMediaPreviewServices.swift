//
//  ChatMediaPreviewServices.swift
//  OutPick
//
//  Created by Codex on 6/19/26.
//

import Foundation
import UIKit

struct ChatVideoPlaybackAsset: Equatable {
    let url: URL
    let storagePath: String?
    var sourcePath: String? = nil
    var fileLease: ChatOriginalFileLease? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.url == rhs.url && lhs.storagePath == rhs.storagePath && lhs.sourcePath == rhs.sourcePath
    }
}

protocol ChatVideoPlaybackResolving {
    func acquireFileForSaving(_ asset: ChatVideoPlaybackAsset) async throws -> ChatOriginalFileLease
    func playbackAsset(forPath path: String) async throws -> ChatVideoPlaybackAsset
    func localFileURLForSaving(
        localURL: URL?,
        storagePath: String?,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL
}

extension ChatVideoPlaybackResolving {
    func acquireFileForSaving(_ asset: ChatVideoPlaybackAsset) async throws -> ChatOriginalFileLease {
        let url = try await localFileURLForSaving(localURL: asset.url, storagePath: asset.storagePath, onProgress: { _ in })
        return ChatOriginalFileLease(fileURL: url, isValid: { true }, release: {})
    }
}

protocol ChatVideoDiskCaching {
    func exists(forKey key: String) async -> URL?
    @discardableResult
    func cache(from remote: URL, key: String) async throws -> URL
    func remove(forKey key: String) async
}

extension ChatVideoDiskCaching {
    func remove(forKey key: String) async {}
}

protocol ChatStorageURLResolving {
    func url(for path: String) async throws -> URL
    func removeCachedURL(for path: String) async
}

extension ChatStorageURLResolving {
    func removeCachedURL(for path: String) async {}
}

protocol ChatRemoteFileDownloading {
    func downloadToTemporaryFile(from remote: URL, onProgress: @escaping (Double) -> Void) async throws -> URL
}

enum ChatMediaPreviewError: LocalizedError, Equatable {
    case emptyPath
    case missingSaveSource
    case photoPermissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .emptyPath:
            return "미디어 경로를 확인할 수 없습니다."
        case .missingSaveSource:
            return "저장할 파일 경로를 확인할 수 없습니다."
        case .photoPermissionDenied:
            return "사진 앱 저장 권한이 필요합니다."
        case .saveFailed:
            return "사진 앱에 저장하지 못했습니다."
        }
    }
}

final class DefaultChatVideoPlaybackResolver: ChatVideoPlaybackResolving {
    private let storageURLResolver: ChatStorageURLResolving
    private let videoDiskCache: ChatVideoDiskCaching
    private let fileDownloader: ChatRemoteFileDownloading
    private let originalFiles: (any ChatOriginalFileLoading)?

    init(
        storageURLResolver: ChatStorageURLResolving,
        videoDiskCache: ChatVideoDiskCaching,
        fileDownloader: ChatRemoteFileDownloading,
        originalFiles: (any ChatOriginalFileLoading)? = nil
    ) {
        self.storageURLResolver = storageURLResolver
        self.videoDiskCache = videoDiskCache
        self.fileDownloader = fileDownloader
        self.originalFiles = originalFiles
    }

    func playbackAsset(forPath path: String) async throws -> ChatVideoPlaybackAsset {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { throw ChatMediaPreviewError.emptyPath }

        if let originalFiles {
            let resource = Self.originalResource(trimmedPath)
            if let lease = try await originalFiles.cachedOriginal(resource) {
                return try await Self.cachedPlaybackAsset(lease: lease, path: trimmedPath)
            }
            let url: URL
            if let local = Self.localFileURL(from: trimmedPath) { url = local }
            else if let remote = Self.directRemoteURL(from: trimmedPath) { url = remote }
            else { url = try await storageURLResolver.url(for: trimmedPath) }
            try Task.checkCancellation()
            // URL 조회 도중 세션이 바뀌었으면 이전 화면에 결과를 넘기지 않는다.
            if let lease = try await originalFiles.cachedOriginal(resource) {
                return try await Self.cachedPlaybackAsset(lease: lease, path: trimmedPath)
            }
            return ChatVideoPlaybackAsset(url: url, storagePath: trimmedPath, sourcePath: trimmedPath)
        }

        if let localURL = Self.localFileURL(from: trimmedPath) {
            return ChatVideoPlaybackAsset(url: localURL, storagePath: nil)
        }

        if let remote = Self.directRemoteURL(from: trimmedPath) {
            return ChatVideoPlaybackAsset(url: remote, storagePath: nil)
        }

        if let cached = await videoDiskCache.exists(forKey: trimmedPath) {
            return ChatVideoPlaybackAsset(url: cached, storagePath: trimmedPath)
        }

        let remote = try await storageURLResolver.url(for: trimmedPath)
        return ChatVideoPlaybackAsset(url: remote, storagePath: trimmedPath)
    }

    static func cachedPlaybackAsset(lease: ChatOriginalFileLease, path: String) async throws -> ChatVideoPlaybackAsset {
        guard !["mp4", "mov", "m4v"].contains(lease.fileURL.pathExtension.lowercased()) else {
            return ChatVideoPlaybackAsset(url: lease.fileURL, storagePath: path, sourcePath: path, fileLease: lease)
        }
        do {
            // 확장자가 없는 원본은 재생용 링크로 제공하고 플레이어 수명 동안 원본 pin을 유지한다.
            let prepared = try PhotoLibraryPreparedResource(fileURL: lease.fileURL, isVideo: true, preferHardLink: true)
            try Task.checkCancellation()
            guard lease.isValid else { throw CancellationError() }
            let playbackLease = ChatOriginalFileLease(fileURL: prepared.fileURL, isValid: { lease.isValid }, release: {
                prepared.cleanup()
                await lease.release()
            })
            return ChatVideoPlaybackAsset(url: playbackLease.fileURL, storagePath: path, sourcePath: path, fileLease: playbackLease)
        } catch {
            await lease.release()
            throw error
        }
    }

    func acquireFileForSaving(_ asset: ChatVideoPlaybackAsset) async throws -> ChatOriginalFileLease {
        guard let originalFiles else {
            let url = try await localFileURLForSaving(localURL: asset.url, storagePath: asset.storagePath, onProgress: { _ in })
            return ChatOriginalFileLease(fileURL: url, isValid: { true }, release: {})
        }
        let path = asset.sourcePath ?? asset.storagePath ?? asset.url.absoluteString
        return try await originalFiles.acquireOriginal(Self.originalResource(path), purpose: .saving)
    }

    private static func originalResource(_ path: String) -> ChatOriginalResource {
        ChatOriginalResource(path: path, maximumBytes: Int(AVAssetExportVideoCompressor.maxChatSourceBytes))
    }

    func localFileURLForSaving(
        localURL: URL?,
        storagePath: String?,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        if let localURL, localURL.isFileURL {
            onProgress(1.0)
            return localURL
        }

        if let storagePath,
           let cached = await videoDiskCache.exists(forKey: storagePath) {
            onProgress(1.0)
            return cached
        }

        if let storagePath,
           !storagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let remote = try await storageURLResolver.url(for: storagePath)
            return try await fileDownloader.downloadToTemporaryFile(from: remote, onProgress: onProgress)
        }

        if let remote = localURL,
           let scheme = remote.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return try await fileDownloader.downloadToTemporaryFile(from: remote, onProgress: onProgress)
        }

        throw ChatMediaPreviewError.missingSaveSource
    }

    private static func localFileURL(from path: String) -> URL? {
        if path.hasPrefix("file://"),
           let url = URL(string: path),
           url.isFileURL {
            return url
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func directRemoteURL(from path: String) -> URL? {
        guard let url = URL(string: path),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }
}

final class URLSessionChatRemoteFileDownloader: ChatRemoteFileDownloading {
    func downloadToTemporaryFile(from remote: URL, onProgress: @escaping (Double) -> Void) async throws -> URL {
        let (tmpURL, _) = try await URLSession.shared.download(from: remote)
        let fileExtension = remote.pathExtension.isEmpty ? "mp4" : remote.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-media-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tmpURL, to: destination)
        onProgress(1.0)
        return destination
    }
}

extension StorageDownloadURLCache: ChatStorageURLResolving {}
extension OPVideoDiskCache: ChatVideoDiskCaching {}
