//
//  FirebaseStorageTransferRepository.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import Foundation
import FirebaseStorage

/// Firebase Storage 업로드(putData/putFile) 공통 로직을 제공하는 리포지토리
final class FirebaseStorageTransferRepository: FirebaseStorageTransferRepositoryProtocol {

    static let shared = FirebaseStorageTransferRepository()

    private let storage = Storage.storage()

    /// Max bytes allowed for putData fallback (default 24MB). Bump to 32MB if needed.
    private var dataFallbackMaxBytes: Int64 = 24 * 1024 * 1024
    /// Serialize big putData fallbacks to reduce peak memory usage
    private let dataFallbackLimiter = AsyncSemaphore(1)

    private init() {}

    var fallbackMaxBytes: Int64 { dataFallbackMaxBytes }

    func fileSize(at url: URL) -> Int64? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber {
            return size.int64Value
        }
        return nil
    }

    func withFallbackLimiter<T>(_ operation: () async throws -> T) async rethrows -> T {
        await dataFallbackLimiter.acquire()
        defer { Task { await self.dataFallbackLimiter.release() } }
        return try await operation()
    }

    /// Clamp to a sane range 8MB...64MB.
    func setDataFallbackLimitMB(_ mb: Int) {
        let clamped = max(8, min(mb, 64))
        self.dataFallbackMaxBytes = Int64(clamped) * 1024 * 1024
    }

    func uploadWithRetry(data: Data,
                         to path: String,
                         contentType: String,
                         uploadFailure: Error,
                         cacheControl: String? = nil,
                         retries: Int = 2,
                         backoff: Double = 0.6,
                         progress: ((Int64, Int64) -> Void)? = nil) async throws -> String {
        var attempt = 0
        var delay = backoff

        while true {
            do {
                return try await upload(
                    data: data,
                    to: path,
                    contentType: contentType,
                    uploadFailure: uploadFailure,
                    cacheControl: cacheControl,
                    progress: progress
                )
            } catch {
                if attempt < retries, shouldRetry(error) {
                    let ns = error as NSError
                    print("↻ retry upload(data) (\(path)) attempt=\(attempt + 1) code=\(ns.code)")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    attempt += 1
                    delay *= 2
                    continue
                }
                throw error
            }
        }
    }

    func uploadFileWithRetry(from fileURL: URL,
                             to path: String,
                             contentType: String,
                             uploadFailure: Error,
                             cacheControl: String? = nil,
                             retries: Int = 2,
                             backoff: Double = 0.6,
                             progress: ((Int64, Int64) -> Void)? = nil) async throws -> String {
        var attempt = 0
        var delay = backoff

        while true {
            do {
                return try await uploadFile(
                    from: fileURL,
                    to: path,
                    contentType: contentType,
                    uploadFailure: uploadFailure,
                    cacheControl: cacheControl,
                    progress: progress
                )
            } catch {
                if attempt < retries, shouldRetry(error) {
                    let ns = error as NSError
                    print("↻ retry uploadFile (\(path)) attempt=\(attempt + 1) code=\(ns.code)")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    attempt += 1
                    delay *= 2
                    continue
                }
                throw error
            }
        }
    }

    @discardableResult
    func upload(data: Data,
                to path: String,
                contentType: String,
                uploadFailure: Error,
                cacheControl: String? = nil,
                progress: ((Int64, Int64) -> Void)? = nil) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let ref = storage.reference().child(path)
            let metadata = StorageMetadata()
            metadata.contentType = contentType
            if let cacheControl {
                metadata.cacheControl = cacheControl
            }

            let task = ref.putData(data, metadata: metadata) { _, error in
                if let error {
                    let ns = error as NSError
                    print("🚫 upload(data) 실패(\(path)): code=\(ns.code) domain=\(ns.domain) desc=\(ns.localizedDescription)")
                    continuation.resume(throwing: uploadFailure)
                    return
                }
                continuation.resume(returning: path)
            }

            _ = task.observe(.progress) { snapshot in
                if let p = snapshot.progress {
                    progress?(p.completedUnitCount, p.totalUnitCount)
                }
            }
        }
    }

    @discardableResult
    func uploadFile(from fileURL: URL,
                    to path: String,
                    contentType: String,
                    uploadFailure: Error,
                    cacheControl: String? = nil,
                    progress: ((Int64, Int64) -> Void)? = nil) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let ref = storage.reference().child(path)
            let metadata = StorageMetadata()
            metadata.contentType = contentType
            if let cacheControl {
                metadata.cacheControl = cacheControl
            }

            let task = ref.putFile(from: fileURL, metadata: metadata) { _, error in
                if let error {
                    let ns = error as NSError
                    print("🚫 uploadFile 실패(\(path)): code=\(ns.code) domain=\(ns.domain) desc=\(ns.localizedDescription)")
                    continuation.resume(throwing: uploadFailure)
                    return
                }
                continuation.resume(returning: path)
            }

            _ = task.observe(.progress) { snapshot in
                if let p = snapshot.progress {
                    progress?(p.completedUnitCount, p.totalUnitCount)
                }
            }
        }
    }

    private func shouldRetry(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == "FIRStorageErrorDomain" {
            // -13000 unknown, -13040 retry limit exceeded, -13030 cancelled
            switch ns.code { case -13000, -13040, -13030: return true; default: break }
        }
        if ns.domain == NSURLErrorDomain {
            return [-999, -1001, -1005, -1009].contains(ns.code)
        }
        if let underlying = (ns.userInfo[NSUnderlyingErrorKey] as? NSError), underlying.domain == NSURLErrorDomain {
            return [-999, -1001, -1005, -1009].contains(underlying.code)
        }
        return false
    }
}

extension FirebaseStorageTransferRepository {
    // Lightweight async semaphore to cap concurrent uploads (permit-based, bug-free)
    actor AsyncSemaphore {
        private var permits: Int
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(_ max: Int) { self.permits = max }

        func acquire() async {
            if permits > 0 {
                permits -= 1
                return
            }
            await withCheckedContinuation { cont in
                waiters.append(cont)
            }
        }

        func release() {
            if !waiters.isEmpty {
                let cont = waiters.removeFirst()
                cont.resume()
            } else {
                permits += 1
            }
        }
    }
}
