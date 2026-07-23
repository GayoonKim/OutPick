import Foundation
import CryptoKit
import UIKit

enum LookbookRemotePreviewImageError: Error {
    case missingRequest
    case invalidResponse
    case responseTooLarge
}

private actor LookbookRemotePreviewRequestStore {
    private var requests: [String: LookbookRemotePreviewImageRequest] = [:]

    func set(_ request: LookbookRemotePreviewImageRequest, for key: String) {
        requests[key] = request
    }

    func request(for key: String) -> LookbookRemotePreviewImageRequest? {
        requests[key]
    }

    func remove(_ key: String) {
        requests.removeValue(forKey: key)
    }
}

private actor LookbookRemotePreviewLoadCoordinator {
    private var tasks: [String: Task<UIImage, Error>] = [:]

    func image(
        for key: String,
        operation: @escaping @Sendable () async throws -> UIImage
    ) async throws -> UIImage {
        if let task = tasks[key] {
            return try await task.value
        }

        let task = Task { try await operation() }
        tasks[key] = task
        do {
            let image = try await task.value
            tasks.removeValue(forKey: key)
            return image
        } catch {
            tasks.removeValue(forKey: key)
            throw error
        }
    }
}

final class LookbookRemotePreviewImageLoader: LookbookRemotePreviewImageLoading {
    typealias FetchData = @Sendable (
        _ request: LookbookRemotePreviewImageRequest,
        _ maxBytes: Int
    ) async throws -> Data

    private let requestStore: LookbookRemotePreviewRequestStore
    private let loadCoordinator: LookbookRemotePreviewLoadCoordinator
    private let pipeline: ImageCachePipeline

    init(
        fetchData: @escaping FetchData = { request, maxBytes in
            try await LookbookRemotePreviewImageLoader.fetchData(
                request: request,
                maxBytes: maxBytes
            )
        }
    ) {
        let requestStore = LookbookRemotePreviewRequestStore()
        self.requestStore = requestStore
        self.loadCoordinator = LookbookRemotePreviewLoadCoordinator()
        self.pipeline = ImageCachePipeline(
            fetcher: { key, maxBytes in
                guard let request = await requestStore.request(for: key) else {
                    throw LookbookRemotePreviewImageError.missingRequest
                }
                return try await fetchData(request, maxBytes)
            },
            disk: ImageCacheDiskStore(
                folderName: "LookbookRemotePreviewImageCache",
                maxSizeBytes: 200 * 1024 * 1024
            )
        )
    }

    func loadImage(
        request: LookbookRemotePreviewImageRequest,
        maxBytes: Int
    ) async throws -> UIImage {
        let key = cacheKey(request: request, maxBytes: maxBytes)
        await requestStore.set(request, for: key)
        do {
            let image = try await loadCoordinator.image(for: key) { [pipeline] in
                try await pipeline.loadImage(path: key, maxBytes: maxBytes)
            }
            await requestStore.remove(key)
            return image
        } catch {
            await requestStore.remove(key)
            throw error
        }
    }

    func prefetch(
        requests: [LookbookRemotePreviewImageRequest],
        maxBytes: Int,
        concurrency: Int
    ) async {
        let uniqueRequests = unique(requests)
        guard !uniqueRequests.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var iterator = uniqueRequests.makeIterator()
            var running = 0

            func spawnNext() {
                guard let request = iterator.next() else { return }
                running += 1
                group.addTask { [weak self] in
                    guard let self else { return }
                    _ = try? await self.loadImage(
                        request: request,
                        maxBytes: maxBytes
                    )
                }
            }

            let initial = min(max(1, concurrency), uniqueRequests.count)
            for _ in 0..<initial {
                spawnNext()
            }

            while running > 0 {
                await group.next()
                running -= 1
                spawnNext()
            }
        }
    }

    private func unique(
        _ requests: [LookbookRemotePreviewImageRequest]
    ) -> [LookbookRemotePreviewImageRequest] {
        var seen = Set<LookbookRemotePreviewImageRequest>()
        return requests.filter { seen.insert($0).inserted }
    }

    private func cacheKey(
        request: LookbookRemotePreviewImageRequest,
        maxBytes: Int
    ) -> String {
        let rawKey = [
            "lookbookRemotePreview",
            request.remoteURL.absoluteString,
            request.sourcePageURL?.absoluteString ?? "",
            String(maxBytes)
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(rawKey.utf8))
        return "lookbookRemotePreview|" + digest.map {
            String(format: "%02x", $0)
        }.joined()
    }

    private static func fetchData(
        request: LookbookRemotePreviewImageRequest,
        maxBytes: Int
    ) async throws -> Data {
        var urlRequest = URLRequest(url: request.remoteURL)
        urlRequest.setValue(
            "OutPick/1.0 (iOS; lookbook review preview)",
            forHTTPHeaderField: "User-Agent"
        )
        urlRequest.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let sourcePageURL = request.sourcePageURL {
            urlRequest.setValue(
                sourcePageURL.absoluteString,
                forHTTPHeaderField: "Referer"
            )
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw LookbookRemotePreviewImageError.invalidResponse
        }
        guard data.count <= maxBytes else {
            throw LookbookRemotePreviewImageError.responseTooLarge
        }
        return data
    }
}
