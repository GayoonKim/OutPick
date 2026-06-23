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
}

protocol ChatVideoPlaybackResolving {
    func playbackAsset(forPath path: String) async throws -> ChatVideoPlaybackAsset
    func localFileURLForSaving(
        localURL: URL?,
        storagePath: String?,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL
}

protocol ChatVideoDiskCaching {
    func exists(forKey key: String) async -> URL?
    @discardableResult
    func cache(from remote: URL, key: String) async throws -> URL
}

protocol ChatStorageURLResolving {
    func url(for path: String) async throws -> URL
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

    init(
        storageURLResolver: ChatStorageURLResolving,
        videoDiskCache: ChatVideoDiskCaching,
        fileDownloader: ChatRemoteFileDownloading
    ) {
        self.storageURLResolver = storageURLResolver
        self.videoDiskCache = videoDiskCache
        self.fileDownloader = fileDownloader
    }

    func playbackAsset(forPath path: String) async throws -> ChatVideoPlaybackAsset {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { throw ChatMediaPreviewError.emptyPath }

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
        Task.detached { [videoDiskCache] in
            _ = try? await videoDiskCache.cache(from: remote, key: trimmedPath)
        }
        return ChatVideoPlaybackAsset(url: remote, storagePath: trimmedPath)
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
