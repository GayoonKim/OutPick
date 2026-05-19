//
//  FirebaseVideoStorageRepository.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import Foundation

final class FirebaseVideoStorageRepository: FirebaseVideoStorageRepositoryProtocol {

    static let shared = FirebaseVideoStorageRepository()

    private let transferService: FirebaseStorageTransferRepositoryProtocol

    init(transferService: FirebaseStorageTransferRepositoryProtocol = FirebaseStorageTransferRepository.shared) {
        self.transferService = transferService
    }

    // Storage 업로드 유틸(putFile) — streaming upload with retry + safe putData fallback
    func putVideoFileToStorage(localURL: URL,
                               path: String,
                               contentType: String,
                               onProgress: @escaping (Double) -> Void) async throws {
        // 캐시 정책: 비디오는 7일 정도 캐시
        let cacheControl = "public, max-age=604800" // 7 days

        _ = try await transferService.uploadFileWithRetryAndDataFallback(
            from: localURL,
            to: path,
            contentType: contentType,
            uploadFailure: FirebaseStorageError.FailedToUploadVideo,
            cacheControl: cacheControl,
            progress: { completed, total in
                let fraction = total > 0 ? Double(completed) / Double(total) : 0.0
                onProgress(fraction)
            }
        )
    }

    // Storage 업로드 유틸(putData) — data upload with retry
    func putVideoDataToStorage(data: Data, path: String, contentType: String) async throws {
        // 썸네일/경량 리소스는 더 길게 캐시(30일)
        let cacheControl = "public, max-age=2592000" // 30 days
        _ = try await transferService.uploadWithRetry(
            data: data,
            to: path,
            contentType: contentType,
            uploadFailure: FirebaseStorageError.FailedToUploadVideo,
            cacheControl: cacheControl
        )
    }

    func setDataFallbackLimitMB(_ mb: Int) {
        transferService.setDataFallbackLimitMB(mb)
    }
}
