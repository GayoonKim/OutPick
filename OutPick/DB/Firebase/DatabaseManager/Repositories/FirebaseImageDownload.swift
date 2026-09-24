import Foundation
import FirebaseStorage

/// 취소 요청과 SDK 등록의 경합을 처리한다. 완료 콜백 전에는 전송 permit을 반환하지 않는다.
private final class ImageStorageTaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: StorageDownloadTask?
    private var cancellation: Error?
    private var finished = false

    var hasFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    func install(_ task: StorageDownloadTask) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        self.task = task
        let cancelled = cancellation != nil
        lock.unlock()
        if cancelled { task.cancel() }
    }

    func cancel(_ error: Error = CancellationError()) {
        lock.lock()
        if cancellation == nil { cancellation = error }
        let task = task
        lock.unlock()
        task?.cancel()
    }

    func finish(_ error: Error?) -> Error? {
        lock.lock()
        defer { lock.unlock() }
        finished = true
        task = nil
        return cancellation ?? error
    }
}

enum FirebaseImageDownload {
    static func data(from reference: StorageReference, maxBytes: Int) async throws -> Data {
        let handle = ImageStorageTaskHandle()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let task = reference.getData(maxSize: Int64(max(1, maxBytes))) { data, error in
                    if let error = handle.finish(error) { continuation.resume(throwing: error) }
                    else if let data { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: ImageCachePipelineError.invalidImageData) }
                }
                handle.install(task)
            }
        } onCancel: { handle.cancel() }
    }

    static func file(from reference: StorageReference, to url: URL, maxBytes: Int) async throws {
        let handle = ImageStorageTaskHandle()
        // 진단 인자가 있는 실행에서만 해시 경로와 SDK 종료 순서를 관찰한다.
        let key = reference.fullPath
        let metric = ImageCacheMetrics.shared.begin("firebase.file", key: key)
        ImageCacheMetrics.shared.mark("firebase.file.target", key: url.path, parent: metric?.id)
        defer { ImageCacheMetrics.shared.end(metric) }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = reference.write(toFile: url) { _, error in
                    let finishedError = handle.finish(error)
                    ImageCacheMetrics.shared.mark("firebase.file.callback", key: key, parent: metric?.id,
                        outcome: finishedError is CancellationError ? "cancelled" : finishedError == nil ? "success" : "failure")
                    if let error = finishedError { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
                handle.install(task)
                task.observe(.progress) { snapshot in
                    if handle.hasFinished {
                        ImageCacheMetrics.shared.mark("firebase.file.progressAfterCallback", key: url.path, parent: metric?.id)
                    }
                    if let progress = snapshot.progress,
                       progress.completedUnitCount > Int64(maxBytes) || progress.totalUnitCount > Int64(maxBytes) {
                        handle.cancel(ImageCachePipelineError.imageTooLarge)
                    }
                }
            }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= maxBytes else { throw ImageCachePipelineError.imageTooLarge }
        } onCancel: {
            ImageCacheMetrics.shared.mark("firebase.file.cancelRequested", key: key, parent: metric?.id)
            handle.cancel()
        }
    }
}
