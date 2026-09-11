import Foundation
import PhotosUI
import UniformTypeIdentifiers

enum ChatMediaSourceAcquisition {
    static func acquire(_ result: PHPickerResult, index: Int, directory: URL) async throws -> ChatMediaSelection.Source {
        let provider = result.itemProvider
        let isVideo = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
        let type = isVideo ? UTType.movie.identifier : UTType.image.identifier
        return try await acquire(index: index, directory: directory, isVideo: isVideo) { completion in
            provider.loadFileRepresentation(forTypeIdentifier: type, completionHandler: completion)
        }
    }

    static func acquire(index: Int, directory: URL, isVideo: Bool,
        loadFile: (@escaping @Sendable (URL?, Error?) -> Void) -> Progress) async throws -> ChatMediaSelection.Source {
        #if DEBUG
        let requestStarted = ProcessInfo.processInfo.systemUptime
        print("[MediaQA] event=source_load_started selectionID=\(directory.lastPathComponent) index=\(index) uptime=\(requestStarted) mainThread=\(Thread.isMainThread)")
        #endif
        try Task.checkCancellation()
        let cancellation = AcquisitionCancellation()
        // provider의 임시 파일은 callback 내부에서 앱 소유 파일로 복사한다.
        let source: ChatMediaSelection.Source = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
            let progress = loadFile { url, error in
                // 오류 뒤 취소 콜백이 다시 와도 파일 처리와 continuation 완료는 한 번만 수행한다.
                guard cancellation.claimCompletion() else { return }
                #if DEBUG
                let providerReturned = ProcessInfo.processInfo.systemUptime
                print("[MediaQA] event=source_provider_returned selectionID=\(directory.lastPathComponent) index=\(index) uptime=\(providerReturned) providerMs=\((providerReturned - requestStarted) * 1000) mainThread=\(Thread.isMainThread)")
                #endif
                guard let url, error == nil else {
                    #if DEBUG
                    let failure = (error ?? MediaError.failedToConvertImage) as NSError
                    print("[MediaQA] event=source_load_failed selectionID=\(directory.lastPathComponent) index=\(index) domain=\(failure.domain) code=\(failure.code) uptime=\(ProcessInfo.processInfo.systemUptime)")
                    #endif
                    continuation.resume(throwing: error ?? MediaError.failedToConvertImage)
                    return
                }
                do {
                    let destination = directory.appendingPathComponent(String(index))
                        .appendingPathExtension(url.pathExtension.isEmpty ? "dat" : url.pathExtension)
                    #if DEBUG
                    let copyStarted = ProcessInfo.processInfo.systemUptime
                    #endif
                    try FileManager.default.copyItem(at: url, to: destination)
                    #if DEBUG
                    let copyEnded = ProcessInfo.processInfo.systemUptime
                    let bytes = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
                    print("[MediaQA] event=source_copy_completed selectionID=\(directory.lastPathComponent) index=\(index) uptime=\(copyEnded) copyMs=\((copyEnded - copyStarted) * 1000) totalMs=\((copyEnded - requestStarted) * 1000) bytes=\(bytes) format=\(url.pathExtension.lowercased())")
                    #endif
                    continuation.resume(returning: .init(index: index, path: destination.path, isVideo: isVideo))
                } catch {
                    #if DEBUG
                    let failure = error as NSError
                    print("[MediaQA] event=source_copy_failed selectionID=\(directory.lastPathComponent) index=\(index) domain=\(failure.domain) code=\(failure.code) uptime=\(ProcessInfo.processInfo.systemUptime)")
                    #endif
                    continuation.resume(throwing: error)
                }
            }
            cancellation.install(progress)
            #if DEBUG
            print("[MediaQA] event=source_request_registered selectionID=\(directory.lastPathComponent) index=\(index) uptime=\(ProcessInfo.processInfo.systemUptime)")
            #endif
            }
        } onCancel: {
            #if DEBUG
            print("[MediaQA] event=source_cancel_requested selectionID=\(directory.lastPathComponent) index=\(index) uptime=\(ProcessInfo.processInfo.systemUptime)")
            #endif
            cancellation.cancel()
        }
        try Task.checkCancellation()
        return source
    }
}

private final class AcquisitionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var progress: Progress?
    private var canceled = false
    private var completionClaimed = false
    func claimCompletion() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completionClaimed else { return false }
        completionClaimed = true
        return true
    }
    func install(_ progress: Progress) {
        lock.lock()
        self.progress = progress
        let shouldCancel = canceled
        lock.unlock()
        if shouldCancel { progress.cancel() }
    }
    func cancel() {
        lock.lock()
        canceled = true
        let value = progress
        lock.unlock()
        value?.cancel()
    }
}
