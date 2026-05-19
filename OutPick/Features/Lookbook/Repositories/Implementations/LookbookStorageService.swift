//
//  LookbookStorageService.swift
//  OutPick
//
//  Created by 김가윤 on 12/17/25.
//

import Foundation
import FirebaseStorage
#if canImport(UIKit)
import UIKit
#endif

final class LookbookStorageService: StorageServiceProtocol {
    private let storage: Storage
    private let transferService: FirebaseStorageTransferRepositoryProtocol

    init(
        storage: Storage = Storage.storage(),
        transferService: FirebaseStorageTransferRepositoryProtocol = FirebaseStorageTransferRepository.shared
    ) {
        self.storage = storage
        self.transferService = transferService
    }

    // MARK: - Upload

    func uploadImage(data: Data, to path: String) async throws -> String {
        let contentType = inferImageContentType(path: path, data: data)
        return try await transferService.uploadWithRetry(
            data: data,
            to: path,
            contentType: contentType,
            uploadFailure: LookbookStorageError.uploadFailed(path: path)
        )
    }

    func uploadImageFileWithRetryAndDataFallback(
        from fileURL: URL,
        to path: String,
        contentType: String
    ) async throws -> String {
        let resolvedContentType: String = {
            if !contentType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return contentType
            }
            if let inferred = contentTypeFromPath(path) {
                return inferred
            }
            if let inferred = contentTypeFromPath(fileURL.path) {
                return inferred
            }
            return "image/jpeg"
        }()

        return try await transferService.uploadFileWithRetryAndDataFallback(
            from: fileURL,
            to: path,
            contentType: resolvedContentType,
            uploadFailure: LookbookStorageError.uploadFailed(path: path)
        )
    }

    func uploadVideo(fileURL: URL, to path: String) async throws -> String {
        let contentType = inferVideoContentType(path: path, fileURL: fileURL)
        return try await transferService.uploadFileWithRetryAndDataFallback(
            from: fileURL,
            to: path,
            contentType: contentType,
            uploadFailure: LookbookStorageError.uploadFailed(path: path)
        )
    }

    func uploadImages(_ datas: [Data], to folderPath: String) async throws -> [String] {
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, data) in datas.enumerated() {
                group.addTask {
                    let uniqueID = UUID().uuidString
                    let path = "\(folderPath)/\(uniqueID)"
                    let uploadedPath = try await self.uploadImage(data: data, to: path)
                    return (index, uploadedPath)
                }
            }

            var results = Array(repeating: "", count: datas.count)
            for try await (index, path) in group {
                results[index] = path
            }
            return results
        }
    }

    func uploadImages(_ datas: [Data], to paths: [String]) async throws -> [String] {
        guard datas.count == paths.count else {
            throw LookbookStorageError.invalidInput
        }

        return try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for index in 0..<datas.count {
                let data = datas[index]
                let path = paths[index]
                group.addTask {
                    let uploadedPath = try await self.uploadImage(data: data, to: path)
                    return (index, uploadedPath)
                }
            }

            var results = Array(repeating: "", count: datas.count)
            for try await (index, path) in group {
                results[index] = path
            }
            return results
        }
    }

    // MARK: - Download

    func downloadData(from path: String, maxSize: Int) async throws -> Data {
        let ref = storage.reference(withPath: path)
        let startedAt = CFAbsoluteTimeGetCurrent()

        do {
            let data = try await ref.data(maxSize: Int64(maxSize))
            LookbookImageLoadDebugLog.log(
                "storage success \(LookbookImageLoadDebugLog.pathDetails(path)) bytes=\(data.count) limit=\(maxSize) total=\(LookbookImageLoadDebugLog.milliseconds(since: startedAt))"
            )
            return data
        } catch {
            LookbookImageLoadDebugLog.log(
                "storage failed \(LookbookImageLoadDebugLog.pathDetails(path)) limit=\(maxSize) total=\(LookbookImageLoadDebugLog.milliseconds(since: startedAt)) error=\(error.localizedDescription)"
            )
            throw error
        }
    }

    func downloadFile(from path: String, to localURL: URL) async throws {
        let ref = storage.reference(withPath: path)
        _ = try await ref.writeAsync(toFile: localURL)
    }

    func downloadImage(from path: String, maxSize: Int) async throws -> Data {
        try await downloadData(from: path, maxSize: maxSize)
    }

#if canImport(UIKit)
    func downloadUIImage(from path: String, maxSize: Int) async throws -> UIImage {
        let data = try await downloadData(from: path, maxSize: maxSize)
        guard let image = UIImage(data: data) else {
            throw LookbookStorageError.imageDecodingFailed
        }
        return image
    }
#endif

    func downloadImages(_ paths: [String], maxSize: Int) async throws -> [Data] {
        try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for (index, path) in paths.enumerated() {
                group.addTask {
                    let data = try await self.downloadData(from: path, maxSize: maxSize)
                    return (index, data)
                }
            }

            var results = Array(repeating: Data(), count: paths.count)
            for try await (index, data) in group {
                results[index] = data
            }
            return results
        }
    }

    // MARK: - Delete / Update

    func deleteFile(at path: String) async throws {
        let ref = storage.reference(withPath: path)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ref.delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func updateFile(data: Data, at path: String) async throws -> String {
        try await uploadImage(data: data, to: path)
    }

    func updateMetadata(for path: String, metadata: StorageMetadata) async throws -> StorageMetadata {
        let ref = storage.reference(withPath: path)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StorageMetadata, Error>) in
            ref.updateMetadata(metadata) { result in
                switch result {
                case .success(let updatedMetadata):
                    continuation.resume(returning: updatedMetadata)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private extension LookbookStorageService {
    func inferImageContentType(path: String, data: Data) -> String {
        if let contentType = contentTypeFromPath(path) {
            return contentType
        }
        if let contentType = imageContentTypeFromSignature(data) {
            return contentType
        }
        return "application/octet-stream"
    }

    func inferVideoContentType(path: String, fileURL: URL) -> String {
        if let contentType = contentTypeFromPath(path) {
            return contentType
        }
        if let contentType = contentTypeFromPath(fileURL.path) {
            return contentType
        }
        return "video/mp4"
    }

    func contentTypeFromPath(_ path: String) -> String? {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }

        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic", "heif": return "image/heic"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"
        default: return nil
        }
    }

    func imageContentTypeFromSignature(_ data: Data) -> String? {
        if data.count >= 3 {
            let header = [UInt8](data.prefix(3))
            if header == [0xFF, 0xD8, 0xFF] {
                return "image/jpeg"
            }
        }

        if data.count >= 8 {
            let pngHeader = [UInt8](data.prefix(8))
            if pngHeader == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
                return "image/png"
            }
        }

        if data.count >= 4 {
            let gifHeader = String(decoding: data.prefix(4), as: UTF8.self)
            if gifHeader == "GIF8" {
                return "image/gif"
            }
        }

        if data.count >= 12 {
            let riff = String(decoding: data.prefix(4), as: UTF8.self)
            let webp = String(decoding: data[8..<12], as: UTF8.self)
            if riff == "RIFF", webp == "WEBP" {
                return "image/webp"
            }

            let ftyp = String(decoding: data[4..<8], as: UTF8.self)
            if ftyp == "ftyp" {
                let brand = String(decoding: data[8..<12], as: UTF8.self)
                if ["heic", "heix", "hevc", "hevx", "mif1", "msf1"].contains(brand) {
                    return "image/heic"
                }
            }
        }

        return nil
    }
}

private enum LookbookStorageError: LocalizedError {
    case invalidInput
    case uploadFailed(path: String)
    case imageDecodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "입력 데이터와 경로 개수가 일치하지 않습니다."
        case .uploadFailed(let path):
            return "업로드에 실패했습니다: \(path)"
        case .imageDecodingFailed:
            return "이미지 디코딩에 실패했습니다."
        }
    }
}
