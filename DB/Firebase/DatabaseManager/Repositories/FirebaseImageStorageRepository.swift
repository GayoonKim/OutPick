//
//  FirebaseImageStorageRepository.swift
//  OutPick
//
//  Created by Codex on 2/10/26.
//

import Foundation
import UIKit
import Kingfisher
import FirebaseStorage
import FirebaseFirestore

final class FirebaseImageStorageRepository: FirebaseImageStorageRepositoryProtocol {

    static let shared = FirebaseImageStorageRepository()

    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let transferService: FirebaseStorageTransferRepositoryProtocol

    init(transferService: FirebaseStorageTransferRepositoryProtocol = FirebaseStorageTransferRepository.shared) {
        self.transferService = transferService
    }

    // 채팅방 및 프로필 이미지 업로드
    func uploadImage(
        sha: String,
        uid: String,
        type: ImageLocation,
        thumbData: Data,
        originalFileURL: URL,
        contentType: String = "image/jpeg"
    ) async throws -> (avatarThumbPath: String, avatarPath: String) {

        let thumbPath = "\(type)/\(uid)/thumb/\(sha).jpg"
        let originalPath = "\(type)/\(uid)/original/\(sha).jpg"

        // Cache-Control: 1 year + immutable
        let cacheControl = "public, max-age=31536000, immutable"

        return try await withThrowingTaskGroup(of: (String, Bool).self, returning: (String, String).self) { group in
            // 1) Thumbnail (putData)
            group.addTask { [weak self] in
                guard let self else { throw FirebaseStorageError.FailedToUploadImage }
                let path = try await self.transferService.uploadWithRetry(
                    data: thumbData,
                    to: thumbPath,
                    contentType: contentType,
                    uploadFailure: FirebaseStorageError.FailedToUploadImage,
                    cacheControl: cacheControl
                )
                return (path, true)
            }

            // 2) Original (putFile with retry -> fallback to putData if small)
            group.addTask { [weak self] in
                guard let self else { throw FirebaseStorageError.FailedToUploadImage }
                do {
                    let path = try await self.transferService.uploadFileWithRetry(
                        from: originalFileURL,
                        to: originalPath,
                        contentType: contentType,
                        uploadFailure: FirebaseStorageError.FailedToUploadImage,
                        cacheControl: cacheControl
                    )
                    return (path, false)
                } catch {
                    if let size = self.transferService.fileSize(at: originalFileURL),
                       size <= self.transferService.fallbackMaxBytes {
                        let path = try await self.transferService.withFallbackLimiter {
                            guard let data = try? Data(contentsOf: originalFileURL, options: [.mappedIfSafe]) else {
                                throw error
                            }
                            return try await self.transferService.uploadWithRetry(
                                data: data,
                                to: originalPath,
                                contentType: contentType,
                                uploadFailure: FirebaseStorageError.FailedToUploadImage,
                                cacheControl: cacheControl
                            )
                        }
                        print("✅ avatar original fallback via putData succeeded (\(size) bytes <= limit=\(self.transferService.fallbackMaxBytes)): \(originalPath)")
                        return (path, false)
                    }
                    throw error
                }
            }

            var thumbResult: String?
            var originalResult: String?
            for try await (path, isThumb) in group {
                if isThumb {
                    thumbResult = path
                } else {
                    originalResult = path
                }
            }

            guard let thumb = thumbResult, let original = originalResult else {
                throw FirebaseStorageError.FailedToUploadImage
            }
            return (thumb, original)
        }
    }

    /// Convenience: Upload avatar, then save the new paths to document.
    func uploadAndSave(
        sha: String,
        uid: String,
        type: ImageLocation,
        thumbData: Data,
        originalFileURL: URL,
        versionHint: String? = nil,
        contentType: String = "image/jpeg"
    ) async throws -> (avatarThumbPath: String, avatarPath: String) {
        let _ = versionHint

        let (thumbPath, originalPath) = try await uploadImage(
            sha: sha,
            uid: uid,
            type: type,
            thumbData: thumbData,
            originalFileURL: originalFileURL,
            contentType: contentType
        )

        try await db.collection("\(type)").document(uid).setData([
            "thumbPath": originalPath,
            "originalPath": thumbPath
        ], merge: true)

        return (thumbPath, originalPath)
    }

    // MARK: - Chat image attachment meta
    /// Message용(썸네일 + 원본) 일괄 업로드
    func uploadPairsToRoomMessage(_ pairs: [DefaultMediaProcessingService.ImagePair],
                                  roomID: String,
                                  messageID: String,
                                  cacheTTLThumbDays: Int = 30,
                                  cacheTTLOriginalDays: Int = 7,
                                  cleanupTemp: Bool = true,
                                  onProgress: ((Double) -> Void)? = nil) async throws -> [Attachment] {
        let thumbCacheControl = "public, max-age=\(cacheTTLThumbDays * 24 * 3600)"
        let originalCacheControl = "public, max-age=\(cacheTTLOriginalDays * 24 * 3600)"

        let totalBytes: Int64 = pairs.reduce(0) { partial, pair in
            partial + Int64(pair.thumbData.count) + Int64(pair.bytesOriginal)
        }
        var uploadedBytes: Int64 = 0
        let progressQueue = DispatchQueue(label: "firebase.upload.progress.aggregate")
        var lastReported: [String: Int64] = [:]
        if totalBytes > 0 { onProgress?(0.0) }

        let limiter = FirebaseStorageTransferRepository.AsyncSemaphore(4)

        let (attachments, hadFailure) = await withTaskGroup(of: (Int, Attachment)?.self, returning: ([Attachment], Bool).self) { group in
            for pair in pairs {
                group.addTask { [weak self] () -> (Int, Attachment)? in
                    guard let self else { return nil }
                    await limiter.acquire()
                    defer { Task { await limiter.release() } }

                    let base = pair.fileBaseName
                    let thumbPath = "Rooms/\(roomID)/messages/\(messageID)/Thumb/\(base).jpg"
                    let originalPath = "Rooms/\(roomID)/messages/\(messageID)/Original/\(base).jpg"

                    let fileURL = pair.originalFileURL
                    guard fileURL.isFileURL else {
                        print("🚫 invalid originalFileURL (not file URL): \(fileURL)")
                        return nil
                    }

                    var isDir: ObjCBool = false
                    let exists = FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir)
                    if !exists || isDir.boolValue {
                        print("🚫 original file missing or is directory: \(fileURL.path)")
                        return nil
                    }
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                       let fsize = attrs[.size] as? NSNumber,
                       fsize.int64Value == 0 {
                        print("🚫 original file size is zero: \(fileURL.path)")
                        return nil
                    }

                    do {
                        // 1) 썸네일 업로드(Data)
                        _ = try await self.transferService.uploadWithRetry(
                            data: pair.thumbData,
                            to: thumbPath,
                            contentType: "image/jpeg",
                            uploadFailure: FirebaseStorageError.FailedToUploadImage,
                            cacheControl: thumbCacheControl,
                            progress: { completed, _ in
                                progressQueue.async {
                                    let prev = lastReported[thumbPath] ?? 0
                                    let delta = max(0, completed - prev)
                                    uploadedBytes += delta
                                    lastReported[thumbPath] = completed
                                    if totalBytes > 0 {
                                        onProgress?(Double(uploadedBytes) / Double(totalBytes))
                                    }
                                }
                            }
                        )

                        // 2) 원본 업로드(File URL; 스트리밍) + 실패 시 putData 폴백
                        do {
                            _ = try await self.transferService.uploadFileWithRetry(
                                from: pair.originalFileURL,
                                to: originalPath,
                                contentType: "image/jpeg",
                                uploadFailure: FirebaseStorageError.FailedToUploadImage,
                                cacheControl: originalCacheControl,
                                progress: { completed, _ in
                                    progressQueue.async {
                                        let prev = lastReported[originalPath] ?? 0
                                        let delta = max(0, completed - prev)
                                        uploadedBytes += delta
                                        lastReported[originalPath] = completed
                                        if totalBytes > 0 {
                                            onProgress?(Double(uploadedBytes) / Double(totalBytes))
                                        }
                                    }
                                }
                            )
                        } catch {
                            let ns = error as NSError
                            let underlying = (ns.userInfo[NSUnderlyingErrorKey] as? NSError)
                            let uCode = underlying?.code ?? 0
                            let uDomain = underlying?.domain ?? ""
                            print("⚠️ uploadFile 실패, data 업로드로 폴백 시도 (path=\(originalPath)) code=\(ns.code)/\(ns.domain) underlying=\(uCode)/\(uDomain)")

                            if let size = self.transferService.fileSize(at: pair.originalFileURL),
                               size <= self.transferService.fallbackMaxBytes {
                                _ = try await self.transferService.withFallbackLimiter {
                                    guard let data = try? Data(contentsOf: pair.originalFileURL, options: [.mappedIfSafe]) else {
                                        throw error
                                    }
                                    return try await self.transferService.uploadWithRetry(
                                        data: data,
                                        to: originalPath,
                                        contentType: "image/jpeg",
                                        uploadFailure: FirebaseStorageError.FailedToUploadImage,
                                        cacheControl: originalCacheControl,
                                        progress: { completed, _ in
                                            progressQueue.async {
                                                let prev = lastReported[originalPath] ?? 0
                                                let delta = max(0, completed - prev)
                                                uploadedBytes += delta
                                                lastReported[originalPath] = completed
                                                if totalBytes > 0 {
                                                    onProgress?(Double(uploadedBytes) / Double(totalBytes))
                                                }
                                            }
                                        }
                                    )
                                }
                                print("✅ 폴백 putData 업로드 성공(\(size) bytes <= limit=\(self.transferService.fallbackMaxBytes)): \(originalPath)")
                            } else {
                                throw error
                            }
                        }

                        // 3) 로컬 임시 파일 정리 (성공 시에만)
                        if cleanupTemp {
                            try? FileManager.default.removeItem(at: pair.originalFileURL)
                        }

                        let attachment = Attachment(
                            type: .image,
                            index: pair.index,
                            pathThumb: thumbPath,
                            pathOriginal: originalPath,
                            width: pair.originalWidth,
                            height: pair.originalHeight,
                            bytesOriginal: pair.bytesOriginal,
                            hash: pair.sha256,
                            blurhash: nil,
                            duration: nil
                        )
                        return (pair.index, attachment)
                    } catch {
                        let ns = error as NSError
                        print("🚫 pair 업로드 실패 index=\(pair.index) thumb=\(thumbPath) orig=\(originalPath) code=\(ns.code) domain=\(ns.domain) desc=\(ns.localizedDescription)")
                        return nil
                    }
                }
            }

            var ordered = Array<Attachment?>(repeating: nil, count: pairs.count)
            for await result in group {
                if let (idx, att) = result {
                    ordered[idx] = att
                }
            }

            if totalBytes > 0 { onProgress?(1.0) }

            let hadFailure = ordered.contains(where: { $0 == nil })
            return (ordered.compactMap { $0 }, hadFailure)
        }

        if hadFailure {
            throw FirebaseStorageError.FailedToUploadImage
        }

        return attachments
    }

    enum StorageImageError: Error { case invalidData }

    func fetchImageFromStorage(image: String, location: ImageLocation) async throws -> UIImage {
        let _ = location
        let ref = storage.reference(withPath: image)

        let url = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            ref.downloadURL { url, err in
                if let err {
                    continuation.resume(throwing: err)
                    return
                }
                continuation.resume(returning: url!)
            }
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else {
            throw StorageImageError.invalidData
        }

        return image
    }

    // Storage에서 여러 이미지 불러오는 함수
    func fetchImagesFromStorage(from imagePaths: [String], location: ImageLocation, createdDate: Date) async throws -> [UIImage] {
        let _ = createdDate
        var images = Array<UIImage?>(repeating: nil, count: imagePaths.count)

        try await withThrowingTaskGroup(of: (Int, UIImage).self, returning: Void.self) { group in
            for (index, imagePath) in imagePaths.enumerated() {
                group.addTask {
                    let image = try await self.fetchImageFromStorage(image: imagePath, location: location)
                    return (index, image)
                }
            }

            for try await (index, image) in group {
                images[index] = image
            }
        }

        return images.compactMap { $0 }
    }

    // Storage에 있는 이미지 미리 캐시
    func prefetchImages(paths: [String], location: ImageLocation, createdDate: Date = Date()) {
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.fetchImagesFromStorage(from: paths, location: location, createdDate: createdDate)
            } catch {
                print("⚠️ warmImageCache 실패: \(error)")
            }
        }
    }

    func deleteImageFromStorage(path: String) {
        let fileRef = storage.reference().child(path)
        print(#function, "📄 \(fileRef)")
        fileRef.delete { error in
            if let error {
                print("🚫 이미지 삭제 실패: \(error.localizedDescription)")
            } else {
                print("✅ 이미지 삭제 성공: \(path)")
                KingFisherCacheManager.shared.removeImage(forKey: path)
            }
        }
    }

    func setDataFallbackLimitMB(_ mb: Int) {
        transferService.setDataFallbackLimitMB(mb)
    }
}
