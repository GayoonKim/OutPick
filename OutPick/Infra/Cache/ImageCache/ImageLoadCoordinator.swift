import Foundation
import UIKit

/// 디스크 조회 전부터 동일 작업을 합치고 소비자마다 독립적으로 결과를 전달한다.
actor ImageLoadCoordinator {
    typealias DemandObserver = @Sendable (ImageRequest, ImageRequestPriority?, Int) -> Void
    typealias Promotion = @Sendable (UIImage) async throws -> ImageLoadValue
    private struct PromotionJob {
        let id: UUID
        let task: Task<Void, Never>
    }
    private struct Consumer {
        let priority: ImageRequestPriority
        let continuation: CheckedContinuation<ImageLoadValue, Error>
    }

    private struct Job {
        let id: UUID
        let revision: UInt64
        let context: ImageWorkContext
        var consumers: [UUID: Consumer]
        var storesOnDisk: Bool
        var task: Task<Void, Never>?
    }

    private let memory: ImageCacheMemoryStore
    private let disk: ImageCacheDiskStore
    private let resources: ImagePipelineResources
    private let persistence: ImageCachePersistence
    private let onDemandChange: DemandObserver?
    private let promotion: Promotion?
    private var promotions: [String: PromotionJob] = [:]
    private var jobs: [ImageRequest: Job] = [:]
    private var revisions: [String: UInt64] = [:]
    private var globalRevision: UInt64 = 0

    init(memory: ImageCacheMemoryStore, disk: ImageCacheDiskStore, resources: ImagePipelineResources = .shared, promotion: Promotion? = nil, onDemandChange: DemandObserver? = nil) {
        self.memory = memory
        self.disk = disk
        self.resources = resources
        self.persistence = ImageCachePersistence(disk: disk)
        self.onDemandChange = onDemandChange
        self.promotion = promotion
    }

    func value(
        for request: ImageRequest,
        priority: ImageRequestPriority,
        storePolicy: ImageCacheStorePolicy,
        operation: @escaping @Sendable (UInt64) async throws -> ImageLoadValue
    ) async throws -> ImageLoadValue {
        let consumerID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                // 등록과 조회 사이에 await를 두지 않는다.
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let consumer = Consumer(priority: priority, continuation: continuation)
                if var job = jobs[request] {
                    job.consumers[consumerID] = consumer
                    job.storesOnDisk = job.storesOnDisk || storePolicy == .memoryAndDisk
                    jobs[request] = job
                    notifyDemand(request)
                    ImageCacheMetrics.shared.mark("inflightJoin", key: request.path, outcome: "job_\(job.id)")
                    return
                }

                let id = UUID()
                let revision = currentRevision(request.path)
                let context = ImageWorkContext(priority)
                jobs[request] = Job(id: id, revision: revision, context: context, consumers: [consumerID: consumer], storesOnDisk: storePolicy == .memoryAndDisk)
                let task = Task {
                    let result: Result<ImageLoadValue, Error>
                    do {
                        try Task.checkCancellation()
                        result = .success(try await ImageWorkContext.$current.withValue(context) { try await operation(revision) })
                    } catch {
                        result = .failure(error)
                    }
                    let transferred = await self.complete(request: request, id: id, result: result)
                    if !transferred, case .success(let value) = result { await value.release?() }
                }
                jobs[request]?.task = task
                notifyDemand(request)
            }
        } onCancel: {
            Task { await self.cancel(consumerID: consumerID, request: request) }
        }
    }

    /// Phase 2 scheduler가 조회할 수 있는 실제 수요 우선순위다.
    /// 실행 중인 Task를 재시작하거나 SDK 전송 우선순위를 변경하지 않는다.
    func priority(for request: ImageRequest) -> ImageRequestPriority? {
        guard let job = jobs[request] else { return nil }
        var priorities = job.consumers.values.map(\.priority)
        if case .cache = request.work {
            // load 작업에 visible 소비자가 합류하면 그 작업이 기다리는 캐시 조회도 승격한다.
            for (related, relatedJob) in jobs where related.path == request.path {
                priorities.append(contentsOf: relatedJob.consumers.values.map(\.priority))
            }
        }
        return priorities.max { $0.rawValue < $1.rawValue }
    }

    func consumerCount(for request: ImageRequest) -> Int {
        jobs[request]?.consumers.count ?? 0
    }

    private func cancel(consumerID: UUID, request: ImageRequest) {
        guard var job = jobs[request], let consumer = job.consumers.removeValue(forKey: consumerID) else { return }
        if job.consumers.isEmpty {
            jobs.removeValue(forKey: request)
            job.task?.cancel()
        } else {
            jobs[request] = job
        }
        consumer.continuation.resume(throwing: CancellationError())
        notifyDemand(request)
    }

    private func complete(request: ImageRequest, id: UUID, result: Result<ImageLoadValue, Error>) async -> Bool {
        guard let job = jobs[request], job.id == id, job.revision == currentRevision(request.path) else { return false }
        var transferred = false
        if !request.isTransient, case .success(let value) = result, let image = value.image {
            if priority(for: request) == .diskPreparation {
                memory.setIfRoom(image, forKey: request.cacheKey)
            } else {
                memory.set(image, forKey: request.cacheKey)
            }
            if job.storesOnDisk, let payload = value.payload {
                transferred = true
                await persistence.enqueue(payload, key: request.cacheKey, revision: job.revision, release: value.release)
            } else if job.storesOnDisk {
                schedulePromotion(image: image, path: request.path)
            }
        }
        guard let current = jobs[request], current.id == id,
              current.revision == currentRevision(request.path) else { return transferred }
        jobs.removeValue(forKey: request)
        notifyDemand(request)
        // 소비자가 압축 데이터나 저장 예약의 소유권을 보유하지 않게 한다.
        let delivered = result.map { ImageLoadValue(image: $0.image) }
        for consumer in current.consumers.values { consumer.continuation.resume(with: delivered) }
        return transferred
    }

    func flushPendingWrites() async {
        let pending = promotions.values.map(\.task)
        for task in pending { await task.value }
        await persistence.flush()
    }

    func waitForPendingWrite(path: String, revision: UInt64) async throws {
        try await persistence.wait(forKey: "imageCache|\(path)", revision: revision)
        guard revision == currentRevision(path) else { throw CancellationError() }
    }

    func cachedMemoryImage(path: String, promote: Bool) -> UIImage? {
        guard let image = memory.image(forKey: "imageCache|\(path)") else { return nil }
        if promote { schedulePromotion(image: image, path: path) }
        return image
    }

    private func schedulePromotion(image: UIImage, path: String) {
        guard let promotion, promotions[path] == nil else { return }
        let revision = currentRevision(path)
        let id = UUID()
        let task = Task(priority: .utility) {
            await ImageWorkContext.$current.withValue(ImageWorkContext(.prefetch)) {
                await self.promote(image: image, path: path, revision: revision, id: id, using: promotion)
            }
        }
        promotions[path] = PromotionJob(id: id, task: task)
    }

    private func promote(image: UIImage, path: String, revision: UInt64, id: UUID, using encode: Promotion) async {
        defer { if promotions[path]?.id == id { promotions.removeValue(forKey: path) } }
        let key = "imageCache|\(path)"
        // 진행 중인 원래 다운로드 저장이 있으면 먼저 수렴시킨다.
        await persistence.flush()
        guard !Task.isCancelled, revision == currentRevision(path), promotions[path]?.id == id else { return }
        guard await disk.size(forKey: key, revision: revision) == nil else { return }
        guard !Task.isCancelled, revision == currentRevision(path), promotions[path]?.id == id else { return }
        do {
            let value = try await encode(image)
            guard !Task.isCancelled, revision == currentRevision(path), promotions[path]?.id == id,
                  let payload = value.payload else {
                await value.release?()
                return
            }
            await persistence.enqueue(payload, key: key, revision: revision, release: value.release)
            // 파일이 기록되기 전 job을 없애면 다음 hit가 같은 변환을 반복할 수 있다.
            await persistence.flush()
        } catch {
            // 저장 실패는 이미 표시한 이미지를 지우지 않는다. 다음 수요에서 다시 시도한다.
            ImageCacheMetrics.shared.mark("cachePromotion", key: path, outcome: Task.isCancelled ? "cancelled" : "failed")
        }
    }

    func remove(path: String) async {
        let revision = invalidate(path: path)
        memory.remove(forKey: "imageCache|\(path)")
        await disk.remove(forKey: "imageCache|\(path)", revision: revision)
    }

    func store(image: UIImage, data: Data, path: String) async throws {
        try await store(image: image, payload: .data(data), path: path)
    }

    func store(image: UIImage, payload: ImageCachePayload, path: String) async throws {
        try Task.checkCancellation()
        let revision = invalidate(path: path)
        memory.set(image, forKey: "imageCache|\(path)")
        await disk.write(payload: payload, forKey: "imageCache|\(path)", revision: revision)
    }

    /// 변환 전에 세대를 확보해 변환 중 삭제된 이미지가 다시 저장되지 않게 한다.
    func beginPreparedStore(path: String) throws -> UInt64 {
        try Task.checkCancellation()
        return invalidate(path: path)
    }

    func storePrepared(_ value: ImageLoadValue, path: String, revision: UInt64) async throws {
        try Task.checkCancellation()
        guard revision == currentRevision(path) else { throw CancellationError() }
        guard let image = value.image, let payload = value.payload else { throw ImageCachePipelineError.invalidImageData }
        memory.set(image, forKey: "imageCache|\(path)")
        // 준비가 끝난 payload와 예약은 화면 호출자가 아닌 persistence가 해제한다.
        await persistence.enqueue(payload, key: "imageCache|\(path)", revision: revision, release: value.release)
    }

    func removeAll() async {
        globalRevision = ImageCacheRevisionClock.next()
        revisions.removeAll()
        for job in promotions.values { job.task.cancel() }
        promotions.removeAll()
        let oldJobs = Array(jobs.values)
        let oldRequests = Array(jobs.keys)
        jobs.removeAll()
        memory.removeAll()
        for job in oldJobs { cancel(job) }
        for request in oldRequests { notifyDemand(request) }
        await disk.removeAll(revision: globalRevision)
    }

    private func invalidate(path: String) -> UInt64 {
        let revision = ImageCacheRevisionClock.next()
        revisions[path] = revision
        promotions.removeValue(forKey: path)?.task.cancel()
        let requests = jobs.keys.filter { $0.path == path }
        for request in requests {
            if let job = jobs.removeValue(forKey: request) { cancel(job) }
            notifyDemand(request)
        }
        return revision
    }

    private func cancel(_ job: Job) {
        job.task?.cancel()
        for consumer in job.consumers.values {
            consumer.continuation.resume(throwing: CancellationError())
        }
    }

    private func currentRevision(_ path: String) -> UInt64 {
        max(globalRevision, revisions[path] ?? 0)
    }

    private func notifyDemand(_ request: ImageRequest) {
        if let priority = priority(for: request) { jobs[request]?.context.update(priority) }
        resources.reprioritize()
        onDemandChange?(request, priority(for: request), consumerCount(for: request))
        if case .load = request.work {
            let cacheRequest = ImageRequest(path: request.path, work: .cache)
            if jobs[cacheRequest] != nil {
                if let priority = priority(for: cacheRequest) { jobs[cacheRequest]?.context.update(priority) }
                onDemandChange?(cacheRequest, priority(for: cacheRequest), consumerCount(for: cacheRequest))
            }
        }
    }
}
