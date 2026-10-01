import Foundation

actor ChatOriginalFileStore {
    static let shared = ChatOriginalFileStore()
    nonisolated let generation = ChatOriginalGeneration()
    private struct Entry {
        let id = UUID()
        let url: URL
        let bytes: Int
        let persistent: Bool
        let mediaExpiresAt: Date
        let validity = ChatOriginalValidity()
        var pins = 0
        var accessed: Date
        let permit: ImageStageGate.Lease?
    }
    private struct Consumer {
        let session: ChatOriginalSession
        let cancellation: ChatOriginalValidity
        let maximumBytes: Int
        let mediaExpiresAt: Date
        let continuation: CheckedContinuation<ChatOriginalFileLease, Error>
    }
    private struct Flight {
        let key: ChatOriginalFileKey
        let context: ImageWorkContext
        let task: Task<Void, Never>
        var consumers: [UUID: Consumer]
    }
    struct Usage: Sendable {
        let cachedBytes: Int
        let temporaryBytes: Int
        let legacyBytes: Int
        let activeTransfers: Int
        let consumers: Int
        var combinedBytes: Int { cachedBytes + temporaryBytes + legacyBytes }
    }

    private let disk: ChatOriginalFileDisk?
    private let capacity: Int
    private let resources: ImagePipelineResources
    private let legacyRoots: [URL]
    private let now: @Sendable () -> Date
    private var entries: [ChatOriginalFileKey: Entry] = [:]
    private var flights: [UUID: Flight] = [:]
    private var pending: [ChatOriginalFileKey: UUID] = [:]
    private var removedResources: Set<String> = []

    init(root: URL? = nil, capacity: Int = 512 * 1024 * 1024,
         resources: ImagePipelineResources = .shared, legacyRoots: [URL]? = nil,
         now: @escaping @Sendable () -> Date = { Date() }) {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let disk = try? ChatOriginalFileDisk(root: root ?? base.appendingPathComponent("ChatOriginalFiles/v2", isDirectory: true))
        self.disk = disk
        self.capacity = max(0, capacity)
        self.resources = resources
        self.now = now
        self.legacyRoots = legacyRoots ?? (root == nil ? ["ChatImageCache", "ChatOriginalFiles/v1", "Videos"].map { base.appendingPathComponent($0) } : [])
        let currentTime = now()
        for (key, url, bytes, accessed, mediaExpiresAt) in disk?.inventory() ?? [] where mediaExpiresAt > currentTime {
            entries[key] = Entry(url: url, bytes: bytes, persistent: true, mediaExpiresAt: mediaExpiresAt, accessed: accessed, permit: nil)
        }
    }

    func cached(_ resource: ChatOriginalResource, accountID: String, session: ChatOriginalSession) throws -> ChatOriginalFileLease? {
        try validate(resource, accountID: accountID, session: session)
        let key = ChatOriginalFileKey(accountID: accountID, resource: resource)
        guard let entry = entries[key], entry.validity.isValid else { return nil }
        guard entry.mediaExpiresAt > now() else {
            invalidate { $0 == key }
            throw URLError(.resourceUnavailable)
        }
        guard FileManager.default.fileExists(atPath: entry.url.path) else {
            entries.removeValue(forKey: key)
            return nil
        }
        guard entry.bytes <= resource.maximumBytes else { throw ImageCachePipelineError.imageTooLarge }
        return lease(key, session: session)
    }

    func acquire(_ resource: ChatOriginalResource, accountID: String, session: ChatOriginalSession,
                 transport: any ChatOriginalFileTransport) async throws -> ChatOriginalFileLease {
        if let value = try cached(resource, accountID: accountID, session: session) {
            ImageCacheMetrics.shared.mark("original.cache", key: resource.path, outcome: "hit")
            return value
        }
        ImageCacheMetrics.shared.mark("original.cache", key: resource.path, outcome: "miss")
        guard let disk else { throw CocoaError(.fileWriteUnknown) }
        let key = ChatOriginalFileKey(accountID: accountID, resource: resource)
        let consumerID = UUID(), cancellation = ChatOriginalValidity()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let value = try await withCheckedThrowingContinuation { continuation in
                let consumer = Consumer(
                    session: session,
                    cancellation: cancellation,
                    maximumBytes: resource.maximumBytes,
                    mediaExpiresAt: resource.mediaExpiresAt ?? .distantFuture,
                    continuation: continuation
                )
                if let id = pending[key], flights[id] != nil {
                    ImageCacheMetrics.shared.mark("original.transfer", key: resource.path, outcome: "joined")
                    flights[id]?.consumers[consumerID] = consumer
                    if let flight = flights[id], let priority = ImageWorkContext.current?.priority,
                       priority.rawValue > flight.context.priority.rawValue {
                        flight.context.update(priority)
                        resources.reprioritize()
                    }
                    return
                }
                let id = UUID(), temporary = disk.temporaryURL(ext: key.ext)
                let context = ImageWorkContext.current ?? ImageWorkContext(.visible)
                let resources = resources
                let task = Task {
                    var filePermit: ImageStageGate.Lease?
                    var networkPermit: ImageStageGate.Lease?
                    do {
                        filePermit = try await ImageCacheMetrics.shared.request("original.fileGate", key: resource.path) {
                            try await resources.files.acquire(context: context)
                        }
                        networkPermit = try await ImageCacheMetrics.shared.request("original.networkGate", key: resource.path) {
                            try await resources.network.acquire(context: context)
                        }
                        try Task.checkCancellation()
                        try await ImageCacheMetrics.shared.request("original.download", key: resource.path) {
                            try await transport.download(resource, to: temporary)
                        }
                        ImageCacheMetrics.shared.mark("original.downloadBytes", key: resource.path,
                                                     bytes: (try? disk.size(temporary)) ?? 0)
                        await networkPermit?.release()
                        networkPermit = nil
                        try Task.checkCancellation()
                        self.finish(id, temporary: temporary, maximumBytes: resource.maximumBytes, permit: filePermit)
                    } catch {
                        // SDK 완료까지 기다린 뒤에만 파일 삭제와 permit 반환을 수행한다.
                        await networkPermit?.release()
                        disk.remove(temporary)
                        await filePermit?.release()
                        self.fail(id, error: error)
                    }
                }
                flights[id] = Flight(key: key, context: context, task: task, consumers: [consumerID: consumer])
                pending[key] = id
            }
            guard !Task.isCancelled, value.isValid else {
                await value.release()
                throw CancellationError()
            }
            return value
        } onCancel: {
            cancellation.invalidate()
            Task { await self.cancel(consumerID) }
        }
    }

    func endSession(_ id: UUID) {
        let ids = flights.values.flatMap { $0.consumers.filter { $0.value.session.id == id }.map(\.key) }
        for consumer in ids { cancel(consumer) }
    }

    func remove(path: String, accountID: String) {
        let key = ChatOriginalFileKey(accountID: accountID, resource: ChatOriginalResource(path: path))
        removedResources.insert(resourceID(key))
        invalidate { $0.account == key.account && $0.resource == key.resource }
    }

    func removeAll() {
        generation.advance()
        for flight in flights.values { removedResources.insert(resourceID(flight.key)) }
        for key in entries.keys { removedResources.insert(resourceID(key)) }
        invalidate { _ in true }
    }

    func removeExpired(at now: Date) -> Bool {
        let expiredConsumers = flights.values.flatMap { flight in
            flight.consumers.compactMap { id, consumer in
                consumer.mediaExpiresAt <= now ? id : nil
            }
        }
        for consumerID in expiredConsumers { cancel(consumerID) }
        let expiredKeys = Set(entries.compactMap { key, entry in entry.mediaExpiresAt <= now ? key : nil })
        for key in expiredKeys { removedResources.insert(resourceID(key)) }
        invalidate { expiredKeys.contains($0) }
        let diskSucceeded = disk?.removeExpiredFiles(at: now, excluding: Set(entries.keys)) ?? true
        return diskSucceeded && !entries.contains { $0.value.mediaExpiresAt <= now }
    }

    func usage() -> Usage {
        Usage(cachedBytes: entries.values.filter(\.persistent).reduce(0) { $0 + $1.bytes },
              temporaryBytes: ChatOriginalFileDisk.bytes(in: disk.map { [$0.temporary] } ?? []),
              legacyBytes: ChatOriginalFileDisk.bytes(in: legacyRoots), activeTransfers: flights.count,
              consumers: flights.values.reduce(0) { $0 + $1.consumers.count })
    }

    private func validate(_ resource: ChatOriginalResource, accountID: String, session: ChatOriginalSession) throws {
        try Task.checkCancellation()
        guard session.validity.isValid, session.storeGeneration == generation.value else { throw CancellationError() }
        guard !accountID.isEmpty, !resource.path.isEmpty, resource.maximumBytes > 0 else { throw URLError(.badURL) }
        let key = ChatOriginalFileKey(accountID: accountID, resource: resource)
        guard !removedResources.contains(resourceID(key)) else { throw CancellationError() }
        if let mediaExpiresAt = resource.mediaExpiresAt,
           ChatMediaExpiryPolicy.isExpired(mediaExpiresAt, now: now()) {
            throw URLError(.resourceUnavailable)
        }
    }

    private func resourceID(_ key: ChatOriginalFileKey) -> String { key.account + "/" + key.resource }

    private func lease(_ key: ChatOriginalFileKey, session: ChatOriginalSession) -> ChatOriginalFileLease {
        entries[key]!.pins += 1
        entries[key]!.accessed = Date()
        let entry = entries[key]!
        let generation = generation
        let clock = now
        if entry.persistent { disk?.touch(entry.url) }
        return ChatOriginalFileLease(fileURL: entry.url, isValid: {
            session.validity.isValid && entry.validity.isValid && session.storeGeneration == generation.value &&
                entry.mediaExpiresAt > clock()
        }, release: { await self.release(key, entryID: entry.id) })
    }

    private func release(_ key: ChatOriginalFileKey, entryID: UUID) async {
        guard entries[key]?.id == entryID else { return }
        entries[key]!.pins -= 1
        if let entry = entries[key], entry.pins == 0, !entry.persistent || !entry.validity.isValid {
            entries.removeValue(forKey: key)
            disk?.remove(entry.url)
            await entry.permit?.release()
        }
        trim(reserving: 0)
    }

    private func cancel(_ consumerID: UUID) {
        for id in Array(flights.keys) {
            guard let consumer = flights[id]?.consumers.removeValue(forKey: consumerID) else { continue }
            consumer.continuation.resume(throwing: CancellationError())
            if let flight = flights[id], flight.consumers.isEmpty {
                if pending[flight.key] == id { pending.removeValue(forKey: flight.key) }
                flight.task.cancel()
            }
            return
        }
    }

    private func invalidate(where matches: (ChatOriginalFileKey) -> Bool) {
        let consumers = flights.values.filter { matches($0.key) }.flatMap { $0.consumers.keys }
        for id in consumers { cancel(id) }
        for key in Array(entries.keys) where matches(key) {
            guard let entry = entries[key] else { continue }
            entry.validity.invalidate()
            if entry.pins == 0 {
                disk?.remove(entry.url)
                entries.removeValue(forKey: key)
                if let permit = entry.permit { Task { await permit.release() } }
            }
        }
    }

    private func takeFlight(_ id: UUID) -> Flight? {
        guard let flight = flights.removeValue(forKey: id) else { return nil }
        if pending[flight.key] == id { pending.removeValue(forKey: flight.key) }
        return flight
    }

    private func fail(_ id: UUID, error: Error) {
        guard let flight = takeFlight(id) else { return }
        for consumer in flight.consumers.values { consumer.continuation.resume(throwing: error) }
    }

    private func finish(_ id: UUID, temporary: URL, maximumBytes: Int, permit: ImageStageGate.Lease?) {
        guard let disk, let flight = takeFlight(id) else {
            disk?.remove(temporary)
            if let permit { Task { await permit.release() } }
            return
        }
        let consumers = flight.consumers.values.filter {
            $0.session.validity.isValid && $0.cancellation.isValid && $0.mediaExpiresAt > now() &&
                !removedResources.contains(resourceID(flight.key))
        }
        for consumer in flight.consumers.values where !consumer.session.validity.isValid || !consumer.cancellation.isValid ||
            consumer.mediaExpiresAt <= now() || removedResources.contains(resourceID(flight.key)) {
            consumer.continuation.resume(throwing: CancellationError())
        }
        do {
            guard !consumers.isEmpty else { throw CancellationError() }
            let bytes = try disk.size(temporary)
            guard bytes > 0, bytes <= maximumBytes else { throw ImageCachePipelineError.imageTooLarge }
            let mediaExpiresAt = consumers.compactMap(\.mediaExpiresAt).min() ?? .distantFuture
            guard mediaExpiresAt > now() else { throw URLError(.resourceUnavailable) }
            trim(reserving: bytes)
            let current = entries.values.filter(\.persistent).reduce(0) { $0 + $1.bytes }
            let persistent = bytes <= capacity && current <= capacity - bytes
            let url = persistent ? try disk.commit(temporary, key: flight.key, mediaExpiresAt: mediaExpiresAt) : temporary
            entries[flight.key] = Entry(url: url, bytes: bytes, persistent: persistent, mediaExpiresAt: mediaExpiresAt,
                                       accessed: Date(), permit: persistent ? nil : permit)
            for consumer in consumers {
                if bytes <= consumer.maximumBytes {
                    consumer.continuation.resume(returning: lease(flight.key, session: consumer.session))
                } else {
                    consumer.continuation.resume(throwing: ImageCachePipelineError.imageTooLarge)
                }
            }
            if !persistent, let entry = entries[flight.key], entry.pins == 0 {
                entries.removeValue(forKey: flight.key)
                disk.remove(entry.url)
                if let permit { Task { await permit.release() } }
            }
            if persistent, let permit { Task { await permit.release() } }
        } catch {
            disk.remove(temporary)
            if let permit { Task { await permit.release() } }
            for consumer in consumers { consumer.continuation.resume(throwing: error) }
        }
    }

    private func trim(reserving bytes: Int) {
        // 단일 초과 파일 때문에 정상 캐시 전체를 밀어내지 않는다.
        guard bytes <= capacity else { return }
        var total = entries.values.filter(\.persistent).reduce(0) { $0 + $1.bytes }
        for (key, entry) in entries.sorted(by: { $0.value.accessed < $1.value.accessed }) {
            guard total > capacity - bytes else { break }
            guard entry.persistent, entry.pins == 0 else { continue }
            disk?.remove(entry.url)
            entries.removeValue(forKey: key)
            total -= entry.bytes
        }
    }
}
