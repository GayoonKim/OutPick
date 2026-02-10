//
//  FirebaseVideoStorageManager.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import Foundation

final class FirebaseVideoStorageManager {

    static let shared = FirebaseVideoStorageManager()

    private let transferService: FirebaseStorageTransferService

    init(transferService: FirebaseStorageTransferService = .shared) {
        self.transferService = transferService
    }

    // Storage 업로드 유틸(putFile) — streaming upload with retry + safe putData fallback
    func putVideoFileToStorage(localURL: URL,
                               path: String,
                               contentType: String,
                               onProgress: @escaping (Double) -> Void) async throws {
        // 캐시 정책: 비디오는 7일 정도 캐시
        let cacheControl = "public, max-age=604800" // 7 days

        do {
            _ = try await transferService.uploadFileWithRetry(
                from: localURL,
                to: path,
                contentType: contentType,
                uploadFailure: StorageError.FailedToUploadVideo,
                cacheControl: cacheControl,
                progress: { completed, total in
                    let fraction = total > 0 ? Double(completed) / Double(total) : 0.0
                    onProgress(fraction)
                }
            )
        } catch {
            // 파일 업로드가 반복 실패하면, 용량 한도 이하에서는 Data 방식으로 폴백 시도
            if let size = transferService.fileSize(at: localURL),
               size <= transferService.fallbackMaxBytes {
                _ = try await transferService.withFallbackLimiter {
                    guard let data = try? Data(contentsOf: localURL, options: [.mappedIfSafe]) else {
                        throw error
                    }
                    return try await transferService.uploadWithRetry(
                        data: data,
                        to: path,
                        contentType: contentType,
                        uploadFailure: StorageError.FailedToUploadVideo,
                        cacheControl: cacheControl,
                        progress: { completed, total in
                            let fraction = total > 0 ? Double(completed) / Double(total) : 0.0
                            onProgress(fraction)
                        }
                    )
                }
                print("✅ putVideoFileToStorage fallback via putData succeeded (\(size) bytes <= limit=\(transferService.fallbackMaxBytes)): \(path)")
            } else {
                throw error
            }
        }
    }

    // Storage 업로드 유틸(putData) — data upload with retry
    func putVideoDataToStorage(data: Data, path: String, contentType: String) async throws {
        // 썸네일/경량 리소스는 더 길게 캐시(30일)
        let cacheControl = "public, max-age=2592000" // 30 days
        _ = try await transferService.uploadWithRetry(
            data: data,
            to: path,
            contentType: contentType,
            uploadFailure: StorageError.FailedToUploadVideo,
            cacheControl: cacheControl
        )
    }

    func setDataFallbackLimitMB(_ mb: Int) {
        transferService.setDataFallbackLimitMB(mb)
    }
}
