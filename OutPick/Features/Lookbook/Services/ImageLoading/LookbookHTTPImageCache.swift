import Foundation
import UIKit
import CryptoKit

struct LookbookHTTPImageRequest: Hashable {
    let remoteURL: URL
    let sourcePageURL: URL?
    let maxBytes: Int

    var key: String {
        let source = ["lookbook-asset-v1", remoteURL.absoluteString,
                      sourcePageURL?.absoluteString ?? "", String(maxBytes)].joined(separator: "\n")
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum LookbookHTTPImageError: Error {
    case invalidResponse
    case responseTooLarge
    case invalidImage
    case permanentStatus(Int)
    case transientStatus(Int)
}

/// 외부 URL의 body와 HTTP 유효기간을 함께 관리한다. Storage 캐시에는 HTTP TTL을 적용하지 않는다.
actor LookbookHTTPImageCache {
    typealias Fetch = @Sendable (URLRequest, Int) async throws -> (Data, HTTPURLResponse)

    struct CachedImage {
        let image: UIImage
        let isFresh: Bool
        let requiresValidation: Bool
    }

    private struct Metadata: Codable {
        let schemaVersion: Int
        let bodyKey: String
        let contentHash: String
        let expiresAt: Date
        let requiresValidation: Bool
        let eTag: String?
        let lastModified: String?
    }

    private struct Policy {
        let expiresAt: Date
        let requiresValidation: Bool
        let noStore: Bool
    }

    private struct Flight {
        let id: UUID
        let task: Task<UIImage, Error>
        var consumers: Set<UUID>
    }

    static let shared = LookbookHTTPImageCache()
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private let resources: ImagePipelineResources
    private let disk: ImageCacheDiskStore
    private let metadataDirectory: URL
    private let fetch: Fetch
    private let now: @Sendable () -> Date
    private let memory = NSCache<NSString, UIImage>()
    private var metadata: [String: Metadata] = [:]
    private var flights: [String: Flight] = [:]
    private var pendingWrites: [String: Task<Void, Never>] = [:]
    private var pendingWriteIDs: [String: UUID] = [:]
    private var retryState: [String: (attempts: Int, after: Date)] = [:]
    private var permanentErrors: [String: Int] = [:]

    init(
        resources: ImagePipelineResources = .shared,
        directory: URL? = nil,
        fetch: @escaping Fetch = LookbookHTTPImageCache.fetchHTTP,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.resources = resources
        self.disk = ImageCacheDiskStore(
            folderName: "LookbookHTTPImageBodies",
            resources: resources,
            maxSizeBytes: 100 * 1024 * 1024
        )
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.metadataDirectory = directory ?? caches.appendingPathComponent("LookbookHTTPImageMetadata", isDirectory: true)
        self.fetch = fetch
        self.now = now
        memory.totalCostLimit = 48 * 1024 * 1024
        try? FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
    }

    func cachedImage(for request: LookbookHTTPImageRequest) async -> CachedImage? {
        guard let entry = await readMetadata(for: request.key) else { return nil }
        let isFresh = !entry.requiresValidation && entry.expiresAt > now()
        if let image = memory.object(forKey: request.key as NSString) {
            return CachedImage(image: image, isFresh: isFresh, requiresValidation: entry.requiresValidation)
        }
        guard let size = await disk.size(forKey: entry.bodyKey, revision: 0),
              size <= request.maxBytes else {
            if Task.isCancelled { return nil }
            await discard(key: request.key, bodyKey: entry.bodyKey)
            return nil
        }
        // 본문을 메모리에 올리기 전에 예약해 디코딩 대기 데이터도 용량 제한 안에 둔다.
        guard let decodeLease = try? await resources.decodeBytes.acquire(max(1, size)) else { return nil }
        let image: UIImage
        do {
            guard let data = await disk.read(forKey: entry.bodyKey, maxBytes: max(1, size)) else {
                await decodeLease.release()
                if !Task.isCancelled { await discard(key: request.key, bodyKey: entry.bodyKey) }
                return nil
            }
            image = try await prepare(data)
            await decodeLease.release()
        } catch {
            await decodeLease.release()
            if error is CancellationError || Task.isCancelled { return nil }
            await discard(key: request.key, bodyKey: entry.bodyKey)
            return nil
        }
        memory.setObject(image, forKey: request.key as NSString, cost: Self.imageCost(image))
        return CachedImage(image: image, isFresh: isFresh, requiresValidation: entry.requiresValidation)
    }

    /// 여러 카드가 같은 URL을 요구하면 하나의 검증에 합류한다. 마지막 소비자가 취소하면 전송도 취소한다.
    func updatedImage(for request: LookbookHTTPImageRequest) async throws -> UIImage {
        try Task.checkCancellation()
        let cached = await cachedImage(for: request)
        try Task.checkCancellation()
        if let cached, cached.isFresh { return cached.image }
        let key = request.key
        if let status = permanentErrors[key] { throw LookbookHTTPImageError.permanentStatus(status) }
        if let retry = retryState[key], retry.attempts >= 3 || retry.after > now() {
            if let cached, !cached.requiresValidation { return cached.image }
            throw LookbookHTTPImageError.transientStatus(0)
        }

        let consumer = UUID()
        let flight: Flight
        if var existing = flights[key] {
            existing.consumers.insert(consumer)
            flights[key] = existing
            flight = existing
        } else {
            let id = UUID()
            let task = Task { [self] in try await revalidate(request: request, cached: cached) }
            flight = Flight(id: id, task: task, consumers: [consumer])
            flights[key] = flight
        }
        return try await withTaskCancellationHandler {
            do {
                let image = try await flight.task.value
                release(key: key, flightID: flight.id, consumer: consumer)
                try Task.checkCancellation()
                return image
            } catch {
                release(key: key, flightID: flight.id, consumer: consumer)
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                if let cached, !cached.requiresValidation,
                   !(error is LookbookHTTPImageError && Self.isPermanent(error)) {
                    return cached.image
                }
                throw error
            }
        } onCancel: {
            Task { await self.release(key: key, flightID: flight.id, consumer: consumer) }
        }
    }

    func resetRetry(for request: LookbookHTTPImageRequest) {
        retryState.removeValue(forKey: request.key)
        permanentErrors.removeValue(forKey: request.key)
    }

    func flushPendingWrites() async {
        for task in Array(pendingWrites.values) { await task.value }
    }

    private func release(key: String, flightID: UUID, consumer: UUID) {
        guard var flight = flights[key], flight.id == flightID else { return }
        flight.consumers.remove(consumer)
        if flight.consumers.isEmpty {
            flight.task.cancel()
            flights.removeValue(forKey: key)
        } else {
            flights[key] = flight
        }
    }

    private func revalidate(request: LookbookHTTPImageRequest, cached: CachedImage?, allowMissingBodyRecovery: Bool = true) async throws -> UIImage {
        let key = request.key
        if let pending = pendingWrites[key] { await pending.value }
        let previous = await readMetadata(for: key)
        var urlRequest = URLRequest(url: request.remoteURL, cachePolicy: .reloadIgnoringLocalCacheData)
        urlRequest.setValue("OutPick/1.0 (iOS; lookbook asset preview)", forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let referer = request.sourcePageURL?.absoluteString {
            urlRequest.setValue(referer, forHTTPHeaderField: "Referer")
        }
        if let eTag = previous?.eTag {
            urlRequest.setValue(eTag, forHTTPHeaderField: "If-None-Match")
        } else if let modified = previous?.lastModified {
            urlRequest.setValue(modified, forHTTPHeaderField: "If-Modified-Since")
        }

        guard request.maxBytes > 0,
              request.maxBytes <= min(resources.limits.decodeBytes, resources.limits.writeBytes)
        else { throw LookbookHTTPImageError.responseTooLarge }
        let writeLease = try await resources.writeBytes.acquire(request.maxBytes)
        let decodeLease: ImageStageGate.Lease
        do { decodeLease = try await resources.decodeBytes.acquire(request.maxBytes) }
        catch { await writeLease.release(); throw error }
        do {
            let (data, response) = try await resources.network.withPermit {
                try await self.fetch(urlRequest, request.maxBytes)
            }
            try Task.checkCancellation()
            let status = response.statusCode
            if status == 304 {
                await decodeLease.release()
                await writeLease.release()
                guard let previous, let cached else {
                    // 본문이 사라진 304는 조건을 제거해 한 번만 다시 요청한다.
                    guard allowMissingBodyRecovery else { throw LookbookHTTPImageError.invalidResponse }
                    return try await recoverMissingBody(request: request)
                }
                let policy = Self.policy(response: response, previous: previous, at: now())
                let updated = Metadata(schemaVersion: 1, bodyKey: previous.bodyKey,
                                       contentHash: previous.contentHash, expiresAt: policy.expiresAt,
                                       requiresValidation: policy.requiresValidation,
                                       eTag: response.value(forHTTPHeaderField: "ETag") ?? previous.eTag,
                                       lastModified: response.value(forHTTPHeaderField: "Last-Modified") ?? previous.lastModified)
                if policy.noStore { await discard(key: key, bodyKey: previous.bodyKey) }
                else { await saveMetadata(updated, key: key) }
                retryState.removeValue(forKey: key)
                return cached.image
            }
            guard status == 200 else {
                if [401, 403, 404, 410].contains(status) {
                    await discard(key: key, bodyKey: previous?.bodyKey)
                    permanentErrors[key] = status
                    throw LookbookHTTPImageError.permanentStatus(status)
                }
                throw LookbookHTTPImageError.transientStatus(status)
            }
            guard data.count <= request.maxBytes else { throw LookbookHTTPImageError.responseTooLarge }
            await writeLease.reduce(to: max(1, data.count))
            await decodeLease.reduce(to: max(1, data.count))
            let policy = Self.policy(response: response, previous: nil, at: now())
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if let previous, hash == previous.contentHash, let cached {
                await decodeLease.release()
                await writeLease.release()
                let updated = Metadata(schemaVersion: 1, bodyKey: previous.bodyKey,
                                       contentHash: hash, expiresAt: policy.expiresAt,
                                       requiresValidation: policy.requiresValidation,
                                       eTag: response.value(forHTTPHeaderField: "ETag"),
                                       lastModified: response.value(forHTTPHeaderField: "Last-Modified"))
                if policy.noStore { await discard(key: key, bodyKey: previous.bodyKey) }
                else { await saveMetadata(updated, key: key) }
                retryState.removeValue(forKey: key)
                permanentErrors.removeValue(forKey: key)
                return cached.image
            }
            let image = try await prepare(data)
            await decodeLease.release()
            memory.setObject(image, forKey: key as NSString, cost: Self.imageCost(image))
            retryState.removeValue(forKey: key)
            permanentErrors.removeValue(forKey: key)
            if policy.noStore {
                await discard(key: key, bodyKey: previous?.bodyKey)
                await writeLease.release()
            } else {
                let updated = Metadata(schemaVersion: 1, bodyKey: "http|\(key)|\(UUID().uuidString)",
                                       contentHash: hash, expiresAt: policy.expiresAt,
                                       requiresValidation: policy.requiresValidation,
                                       eTag: response.value(forHTTPHeaderField: "ETag"),
                                       lastModified: response.value(forHTTPHeaderField: "Last-Modified"))
                metadata[key] = updated
                let writeID = UUID()
                let task = Task { [self] in
                    await disk.write(data: data, forKey: updated.bodyKey)
                    if await saveMetadata(updated, key: key),
                       let old = previous?.bodyKey { await disk.remove(forKey: old) }
                    await writeLease.release()
                    finishPendingWrite(key: key, id: writeID)
                }
                pendingWrites[key] = task
                pendingWriteIDs[key] = writeID
            }
            return image
        } catch {
            await decodeLease.release()
            await writeLease.release()
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if !Self.isPermanent(error) { recordTransientFailure(for: key) }
            throw error
        }
    }

    private func recoverMissingBody(request: LookbookHTTPImageRequest) async throws -> UIImage {
        await discard(key: request.key, bodyKey: metadata[request.key]?.bodyKey)
        return try await revalidate(request: request, cached: nil, allowMissingBodyRecovery: false)
    }

    private func recordTransientFailure(for key: String) {
        let attempts = min(3, (retryState[key]?.attempts ?? 0) + 1)
        let seconds: TimeInterval = [30, 120, 600][attempts - 1]
        retryState[key] = (attempts, now().addingTimeInterval(seconds))
    }

    private static func isPermanent(_ error: Error) -> Bool {
        if case LookbookHTTPImageError.permanentStatus = error { return true }
        return false
    }

    private static func imageCost(_ image: UIImage) -> Int {
        Int(image.size.width * image.scale) * Int(image.size.height * image.scale) * 4
    }

    private func prepare(_ data: Data) async throws -> UIImage {
        try await resources.decode.withPermit {
            guard let image = ImageFileDecoding.image(data) else { throw LookbookHTTPImageError.invalidImage }
            try Task.checkCancellation()
            return image
        }
    }

    private func readMetadata(for key: String) async -> Metadata? {
        if let entry = metadata[key] { return entry }
        let url = metadataDirectory.appendingPathComponent(key).appendingPathExtension("json")
        guard let data = try? await resources.io.withPermit(kind: .read, operation: {
            try Data(contentsOf: url)
        }), let entry = try? JSONDecoder().decode(Metadata.self, from: data),
              entry.schemaVersion == 1 else { return nil }
        metadata[key] = entry
        return entry
    }

    private func saveMetadata(_ entry: Metadata, key: String) async -> Bool {
        guard metadata[key]?.bodyKey == entry.bodyKey || metadata[key] == nil else { return false }
        metadata[key] = entry
        let url = metadataDirectory.appendingPathComponent(key).appendingPathExtension("json")
        do { try await resources.io.withPermit(kind: .write) {
            try JSONEncoder().encode(entry).write(to: url, options: .atomic)
        }; return true } catch { return false }
    }

    private func finishPendingWrite(key: String, id: UUID) {
        if pendingWriteIDs[key] == id {
            pendingWrites.removeValue(forKey: key)
            pendingWriteIDs.removeValue(forKey: key)
        }
    }

    private func discard(key: String, bodyKey: String?) async {
        metadata.removeValue(forKey: key)
        memory.removeObject(forKey: key as NSString)
        let url = metadataDirectory.appendingPathComponent(key).appendingPathExtension("json")
        _ = try? await resources.io.withPermit(kind: .write) { try? FileManager.default.removeItem(at: url) }
        if let bodyKey { await disk.remove(forKey: bodyKey) }
    }

    private static func policy(response: HTTPURLResponse, previous: Metadata?, at date: Date) -> Policy {
        let directives = (response.value(forHTTPHeaderField: "Cache-Control") ?? "")
            .lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let noStore = directives.contains("no-store")
        let noCache = directives.contains("no-cache") || directives.contains("must-revalidate") ||
            (directives.isEmpty && previous?.requiresValidation == true)
        let maxAge = directives.compactMap { directive -> TimeInterval? in
            guard directive.hasPrefix("max-age=") else { return nil }
            return TimeInterval(directive.dropFirst("max-age=".count))
        }.first
        let age = max(0, TimeInterval(response.value(forHTTPHeaderField: "Age") ?? "") ?? 0)
        let duration = max(0, min(7 * 24 * 60 * 60, maxAge ?? 24 * 60 * 60) - age)
        return Policy(expiresAt: date.addingTimeInterval(duration), requiresValidation: noCache, noStore: noStore)
    }

    private static func fetchHTTP(_ request: URLRequest, maxBytes: Int) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else { throw LookbookHTTPImageError.invalidResponse }
        if response.statusCode != 200 { return (Data(), response) }
        guard response.expectedContentLength <= Int64(maxBytes) else { throw LookbookHTTPImageError.responseTooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maxBytes else { throw LookbookHTTPImageError.responseTooLarge }
            data.append(byte)
        }
        return (data, response)
    }
}
