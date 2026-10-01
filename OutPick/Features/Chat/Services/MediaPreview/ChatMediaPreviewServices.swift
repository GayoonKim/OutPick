import Foundation
import Combine
import UIKit

struct ChatVideoPlaybackAsset: Equatable {
    let url: URL
    let storagePath: String?
    var sourcePath: String? = nil
    var fileLease: ChatOriginalFileLease? = nil
    var resource: ChatVideoPlaybackResource? = nil
    var urlExpiresAt: Date? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.url == rhs.url && lhs.storagePath == rhs.storagePath && lhs.sourcePath == rhs.sourcePath &&
            lhs.resource == rhs.resource && lhs.urlExpiresAt == rhs.urlExpiresAt
    }
}

@MainActor
protocol ChatVideoPlaybackResolving {
    var invalidations: AnyPublisher<String?, Never> { get }
    var isSessionValid: Bool { get }
    func invalidateSession()
    func acquireFileForSaving(_ asset: ChatVideoPlaybackAsset) async throws -> ChatOriginalFileLease
    func playbackAsset(for resource: ChatVideoPlaybackResource, forceRefresh: Bool) async throws -> ChatVideoPlaybackAsset
    func playbackAsset(forPath path: String) async throws -> ChatVideoPlaybackAsset
    func localFileURLForSaving(localURL: URL?, storagePath: String?, onProgress: @escaping (Double) -> Void) async throws -> URL
}

extension ChatVideoPlaybackResolving {
    var invalidations: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var isSessionValid: Bool { true }
    func invalidateSession() {}
    func playbackAsset(for resource: ChatVideoPlaybackResource, forceRefresh: Bool = false) async throws -> ChatVideoPlaybackAsset {
        throw ChatVideoPlaybackError.unavailable
    }
    func localFileURLForSaving(localURL: URL?, storagePath: String?, onProgress: @escaping (Double) -> Void) async throws -> URL {
        throw ChatMediaPreviewError.missingSaveSource
    }
}

protocol ChatVideoDiskCaching {
    func exists(forKey key: String) async -> URL?
    @discardableResult func cache(from remote: URL, key: String) async throws -> URL
    func remove(forKey key: String) async
}
extension ChatVideoDiskCaching { func remove(forKey key: String) async {} }

protocol ChatStorageURLResolving {
    func url(for path: String) async throws -> URL
    func removeCachedURL(for path: String) async
}
extension ChatStorageURLResolving { func removeCachedURL(for path: String) async {} }

enum ChatMediaPreviewError: LocalizedError, Equatable {
    case emptyPath, missingSaveSource, photoPermissionDenied, saveFailed
    var errorDescription: String? {
        switch self {
        case .emptyPath: "미디어 경로를 확인할 수 없습니다."
        case .missingSaveSource: "저장할 파일 경로를 확인할 수 없습니다."
        case .photoPermissionDenied: "사진 앱 저장 권한이 필요합니다."
        case .saveFailed: "사진 앱에 저장하지 못했습니다."
        }
    }
}

/// Container마다 하나를 소유하므로 URL과 진행 요청은 계정 세션 밖으로 공유되지 않는다.
@MainActor
final class DefaultChatVideoPlaybackResolver: ChatVideoPlaybackResolving, ChatStorageURLResolving {
    private let repository: any ChatVideoPlaybackURLRepository
    private let originalFiles: any ChatOriginalFileLoading
    private let now: () -> Date
    private var urls: [ChatVideoPlaybackResource: ChatVideoPlaybackURL] = [:]
    private var flights: [ChatVideoPlaybackResource: (UUID, Task<ChatVideoPlaybackURL, Error>)] = [:]
    private var removedPaths = Set<String>()
    private var cacheTimer: Timer?
    private let invalidationSubject = PassthroughSubject<String?, Never>()
    private(set) var isSessionValid = true
    var invalidations: AnyPublisher<String?, Never> { invalidationSubject.eraseToAnyPublisher() }

    init(repository: any ChatVideoPlaybackURLRepository, originalFiles: any ChatOriginalFileLoading, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.originalFiles = originalFiles
        self.now = now
    }

    func invalidateSession() {
        isSessionValid = false
        cacheTimer?.invalidate()
        urls.removeAll()
        flights.values.forEach { $0.1.cancel() }
        flights.removeAll()
        invalidationSubject.send(nil)
    }

    func removeCachedURL(for path: String) async {
        removedPaths.insert(path)
        urls = urls.filter { $0.key.path != path }
        for key in Array(flights.keys) where key.path == path { flights.removeValue(forKey: key)?.1.cancel() }
        invalidationSubject.send(path)
        scheduleCacheExpiry()
    }

    func url(for path: String) async throws -> URL { throw ChatVideoPlaybackError.unavailable }

    private func validate(_ resource: ChatVideoPlaybackResource) throws {
        try Task.checkCancellation()
        guard isSessionValid else { throw CancellationError() }
        guard !removedPaths.contains(resource.path) else { throw ChatVideoPlaybackError.unavailable }
        guard resource.mediaExpiresAt > now() else {
            urls[resource] = nil
            throw ChatVideoPlaybackError.expired
        }
    }

    func playbackAsset(for resource: ChatVideoPlaybackResource, forceRefresh: Bool = false) async throws -> ChatVideoPlaybackAsset {
        try validate(resource)
        if let lease = try await originalFiles.cachedOriginal(resource.original) {
            do {
                try validate(resource)
                var asset = try await Self.cachedPlaybackAsset(lease: lease, path: resource.path)
                do { try validate(resource) }
                catch { await asset.fileLease?.release(); throw error }
                asset.resource = resource
                return asset
            } catch { await lease.release(); throw error }
        }
        try validate(resource)
        urls = urls.filter { $0.value.urlExpiresAt > now() && $0.key.mediaExpiresAt > now() }
        let ticket: ChatVideoPlaybackURL
        if !forceRefresh, let cached = urls[resource] { ticket = cached }
        else {
            let flight: (UUID, Task<ChatVideoPlaybackURL, Error>)
            if let existing = flights[resource] { flight = existing }
            else {
                flight = (UUID(), Task { try await repository.issue(for: resource) })
                flights[resource] = flight
            }
            do { ticket = try await flight.1.value }
            catch {
                if flights[resource]?.0 == flight.0 { flights[resource] = nil }
                throw error
            }
            if flights[resource]?.0 == flight.0 { flights[resource] = nil }
            try validate(resource)
            guard ticket.urlExpiresAt > now() else { throw ChatVideoPlaybackError.temporarilyUnavailable }
            guard ticket.urlExpiresAt <= resource.mediaExpiresAt,
                  abs(ticket.mediaExpiresAt.timeIntervalSince(resource.mediaExpiresAt)) < 0.001 else {
                throw ChatVideoPlaybackError.invalidResponse
            }
            urls[resource] = ticket
            scheduleCacheExpiry()
        }
        try validate(resource)
        return ChatVideoPlaybackAsset(url: ticket.url, storagePath: resource.path, sourcePath: resource.path,
                                     resource: resource, urlExpiresAt: ticket.urlExpiresAt)
    }

    private func scheduleCacheExpiry() {
        cacheTimer?.invalidate()
        cacheTimer = nil
        urls = urls.filter { $0.value.urlExpiresAt > now() && $0.key.mediaExpiresAt > now() }
        guard isSessionValid, let expiry = urls.values.map(\.urlExpiresAt).min() else { return }
        cacheTimer = Timer.scheduledTimer(withTimeInterval: max(0.01, expiry.timeIntervalSince(now())), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleCacheExpiry() }
        }
        if let cacheTimer { RunLoop.main.add(cacheTimer, forMode: .common) }
    }

    deinit {
        cacheTimer?.invalidate()
        flights.values.forEach { $0.1.cancel() }
    }

    /// 서버 확정 전 outbox의 로컬 파일만 허용한다. 원격 path-only URL은 발급하지 않는다.
    func playbackAsset(forPath path: String) async throws -> ChatVideoPlaybackAsset {
        guard isSessionValid else { throw CancellationError() }
        let local: URL?
        if path.hasPrefix("/") { local = URL(fileURLWithPath: path) }
        else { local = URL(string: path).flatMap { $0.isFileURL ? $0 : nil } }
        guard let local else { throw ChatVideoPlaybackError.unavailable }
        return ChatVideoPlaybackAsset(url: local, storagePath: nil, sourcePath: path)
    }

    static func cachedPlaybackAsset(lease: ChatOriginalFileLease, path: String) async throws -> ChatVideoPlaybackAsset {
        guard lease.isValid else { await lease.release(); throw CancellationError() }
        guard !["mp4", "mov", "m4v"].contains(lease.fileURL.pathExtension.lowercased()) else {
            return ChatVideoPlaybackAsset(url: lease.fileURL, storagePath: path, sourcePath: path, fileLease: lease)
        }
        do {
            let prepared = try PhotoLibraryPreparedResource(fileURL: lease.fileURL, isVideo: true, preferHardLink: true)
            do {
                try Task.checkCancellation()
                guard lease.isValid else { throw CancellationError() }
            } catch { prepared.cleanup(); throw error }
            let playbackLease = ChatOriginalFileLease(fileURL: prepared.fileURL, isValid: { lease.isValid }, release: {
                prepared.cleanup()
                await lease.release()
            })
            return ChatVideoPlaybackAsset(url: playbackLease.fileURL, storagePath: path, sourcePath: path, fileLease: playbackLease)
        } catch { await lease.release(); throw error }
    }

    func acquireFileForSaving(_ asset: ChatVideoPlaybackAsset) async throws -> ChatOriginalFileLease {
        guard isSessionValid else { throw CancellationError() }
        if let resource = asset.resource {
            try validate(resource)
            let lease = try await originalFiles.acquireOriginal(resource.original, purpose: .saving)
            do { try validate(resource); return lease }
            catch { await lease.release(); throw error }
        }
        guard asset.url.isFileURL else { throw ChatMediaPreviewError.missingSaveSource }
        return try await originalFiles.acquireOriginal(
            ChatOriginalResource(path: asset.sourcePath ?? asset.url.path,
                                 maximumBytes: Int(AVAssetExportVideoCompressor.maxChatSourceBytes)), purpose: .saving)
    }
}

extension StorageDownloadURLCache: ChatStorageURLResolving {}
extension OPVideoDiskCache: ChatVideoDiskCaching {}
