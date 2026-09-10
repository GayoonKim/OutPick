import Foundation

protocol ChatMediaForegroundUploading: AnyObject {
    func upload(
        source: ChatMediaSourceDescriptor,
        target: ChatMediaUploadTarget,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> ChatMediaUploadedSource
}

/// 앱이 실행 중인 동안 단일 V4 signed PUT만 수행한다.
/// 재실행 보장은 local outbox와 서버 상태 reconciliation이 담당한다.
final class URLSessionChatMediaForegroundUploader: NSObject, ChatMediaForegroundUploading,
    URLSessionTaskDelegate, @unchecked Sendable {

    private struct PendingUpload {
        let target: ChatMediaUploadTarget
        let continuation: CheckedContinuation<ChatMediaUploadedSource, Error>
        let onProgress: @Sendable (Double) -> Void
    }

    // stateQueue 안에서만 접근하며 콜백 등록 전 취소도 기억한다.
    private final class CancellationState: @unchecked Sendable {
        var canceled = false
    }

    private enum UploadError: LocalizedError {
        case invalidResponse
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "업로드 응답을 확인하지 못했습니다."
            case .http(let status): return "업로드 서버 오류가 발생했습니다. (HTTP \(status))"
            }
        }
    }

    private let stateQueue = DispatchQueue(label: "outpick.chat-media-foreground-upload")
    private var pending: [Int: PendingUpload] = [:]
    private let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration = .default) {
        self.configuration = configuration
        super.init()
    }

    private lazy var session: URLSession = {
        configuration.waitsForConnectivity = false
        configuration.allowsCellularAccess = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func upload(
        source: ChatMediaSourceDescriptor,
        target: ChatMediaUploadTarget,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> ChatMediaUploadedSource {
        var request = URLRequest(url: target.signedURL)
        request.httpMethod = "PUT"
        for (name, value) in target.requiredHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue(String(source.sizeBytes), forHTTPHeaderField: "Content-Length")
        // lazy 세션의 최초 생성도 직렬화해 세션별 taskIdentifier 충돌을 막는다.
        let task = stateQueue.sync {
            session.uploadTask(with: request, fromFile: source.fileURL)
        }
        let cancellation = CancellationState()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                stateQueue.sync {
                    guard !cancellation.canceled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    pending[task.taskIdentifier] = PendingUpload(
                        target: target,
                        continuation: continuation,
                        onProgress: onProgress
                    )
                    task.resume()
                }
            }
        } onCancel: {
            self.stateQueue.sync {
                cancellation.canceled = true
                task.cancel()
                self.pending.removeValue(forKey: task.taskIdentifier)?
                    .continuation.resume(throwing: CancellationError())
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        stateQueue.async {
            guard let upload = self.pending[task.taskIdentifier] else { return }
            let expected = max(upload.target.sizeBytes, 1)
            upload.onProgress(min(1, max(0, Double(totalBytesSent) / Double(expected))))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        stateQueue.async {
            guard let upload = self.pending.removeValue(forKey: task.taskIdentifier) else { return }
            if let error {
                upload.continuation.resume(throwing: error)
                return
            }
            guard let response = task.response as? HTTPURLResponse else {
                upload.continuation.resume(throwing: UploadError.invalidResponse)
                return
            }
            guard (200...299).contains(response.statusCode) else {
                upload.continuation.resume(throwing: UploadError.http(response.statusCode))
                return
            }
            upload.continuation.resume(returning: ChatMediaUploadedSource(
                attachmentID: upload.target.attachmentID,
                sourceIndex: upload.target.sourceIndex,
                path: upload.target.path,
                sizeBytes: upload.target.sizeBytes
            ))
        }
    }
}
