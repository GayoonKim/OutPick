//
//  FirebaseStorageTransferRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 2/19/26.
//

import Foundation

protocol FirebaseStorageTransferRepositoryProtocol {
    func setDataFallbackLimitMB(_ mb: Int)

    func uploadWithRetry(
        data: Data,
        to path: String,
        contentType: String,
        uploadFailure: Error,
        cacheControl: String?,
        retries: Int,
        backoff: Double,
        progress: ((Int64, Int64) -> Void)?
    ) async throws -> String

    func uploadFileWithRetry(
        from fileURL: URL,
        to path: String,
        contentType: String,
        uploadFailure: Error,
        cacheControl: String?,
        retries: Int,
        backoff: Double,
        progress: ((Int64, Int64) -> Void)?
    ) async throws -> String

    func uploadFileWithRetryAndDataFallback(
        from fileURL: URL,
        to path: String,
        contentType: String,
        uploadFailure: Error,
        cacheControl: String?,
        retries: Int,
        backoff: Double,
        progress: ((Int64, Int64) -> Void)?
    ) async throws -> String
}

extension FirebaseStorageTransferRepositoryProtocol {
    func uploadWithRetry(
        data: Data,
        to path: String,
        contentType: String,
        uploadFailure: Error,
        cacheControl: String? = nil,
        retries: Int = 2,
        backoff: Double = 0.6,
        progress: ((Int64, Int64) -> Void)? = nil
    ) async throws -> String {
        try await uploadWithRetry(
            data: data,
            to: path,
            contentType: contentType,
            uploadFailure: uploadFailure,
            cacheControl: cacheControl,
            retries: retries,
            backoff: backoff,
            progress: progress
        )
    }

    func uploadFileWithRetry(
        from fileURL: URL,
        to path: String,
        contentType: String,
        uploadFailure: Error,
        cacheControl: String? = nil,
        retries: Int = 2,
        backoff: Double = 0.6,
        progress: ((Int64, Int64) -> Void)? = nil
    ) async throws -> String {
        try await uploadFileWithRetry(
            from: fileURL,
            to: path,
            contentType: contentType,
            uploadFailure: uploadFailure,
            cacheControl: cacheControl,
            retries: retries,
            backoff: backoff,
            progress: progress
        )
    }

    func uploadFileWithRetryAndDataFallback(
        from fileURL: URL,
        to path: String,
        contentType: String,
        uploadFailure: Error,
        cacheControl: String? = nil,
        retries: Int = 2,
        backoff: Double = 0.6,
        progress: ((Int64, Int64) -> Void)? = nil
    ) async throws -> String {
        try await uploadFileWithRetryAndDataFallback(
            from: fileURL,
            to: path,
            contentType: contentType,
            uploadFailure: uploadFailure,
            cacheControl: cacheControl,
            retries: retries,
            backoff: backoff,
            progress: progress
        )
    }
}
