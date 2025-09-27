//
//  FirebaseMediaManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/10/25.
//


import UIKit
import AVKit
import Foundation
import AVFoundation
import Alamofire
import PhotosUI
import Kingfisher
import Firebase
import FirebaseStorage
import FirebaseFirestore

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
        // resumed: a permit was assigned by release(); nothing to change here.
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

class FirebaseStorageManager {
    
    static let shared = FirebaseStorageManager()
    
    // Firestore 인스턴스
    let db = Firestore.firestore()
    
    // Storage 인스턴스
    let storage = Storage.storage()

    // MARK: - putData fallback tunables
    /// Max bytes allowed for putData fallback (default 24MB). Bump to 32MB if needed.
    private var dataFallbackMaxBytes: Int64 = 24 * 1024 * 1024
    /// Serialize big putData fallbacks to reduce peak memory usage
    private let dataFallbackLimiter = AsyncSemaphore(1)

    // MARK: - Retry helpers
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

    /// Optionally allow tuning the putData fallback limit at runtime.
    /// Clamp to a sane range 8MB...64MB. Call on a serial context if mutating often.
    public func setDataFallbackLimitMB(_ mb: Int) {
        // Clamp to a sane range 8MB...64MB
        let clamped = max(8, min(mb, 64))
        self.dataFallbackMaxBytes = Int64(clamped) * 1024 * 1024
    }

    @discardableResult
    private func uploadWithRetry(data: Data,
                                 to path: String,
                                 contentType: String,
                                 cacheControl: String? = nil,
                                 retries: Int = 2,
                                 backoff: Double = 0.6,
                                 progress: ((Int64, Int64) -> Void)? = nil) async throws -> String {
        var attempt = 0
        var delay = backoff
        while true {
            do {
                return try await upload(data: data, to: path, contentType: contentType, cacheControl: cacheControl, progress: progress)
            } catch {
                if attempt < retries, shouldRetry(error) {
                    let ns = error as NSError
                    print("↻ retry upload(data) (\(path)) attempt=\(attempt+1) code=\(ns.code)")
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
    private func uploadFileWithRetry(from fileURL: URL,
                                     to path: String,
                                     contentType: String,
                                     cacheControl: String? = nil,
                                     retries: Int = 2,
                                     backoff: Double = 0.6,
                                     progress: ((Int64, Int64) -> Void)? = nil) async throws -> String {
        var attempt = 0
        var delay = backoff
        while true {
            do {
                return try await uploadFile(from: fileURL, to: path, contentType: contentType, cacheControl: cacheControl, progress: progress)
            } catch {
                if attempt < retries, shouldRetry(error) {
                    let ns = error as NSError
                    print("↻ retry uploadFile (\(path)) attempt=\(attempt+1) code=\(ns.code)")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    attempt += 1
                    delay *= 2
                    continue
                }
                throw error
            }
        }
    }
    
    // MARK: - Helper: File Size
    private func fileSize(at url: URL) -> Int64? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber {
            return size.int64Value
        }
        return nil
    }

    // MARK: - Generalized upload helpers

    /// Upload arbitrary Data to a Storage path with metadata.
    /// - Returns: the Storage path (same as `to`)
    @discardableResult
    func upload(data: Data,
                to path: String,
                contentType: String,
                cacheControl: String? = nil,
                progress: ((Int64, Int64) -> Void)? = nil) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let ref = storage.reference().child(path)
            let meta = StorageMetadata()
            meta.contentType = contentType
            if let cc = cacheControl {
                meta.cacheControl = cc
            }
            let task = ref.putData(data, metadata: meta) { _, error in
                if let error = error {
                    let ns = error as NSError
                    print("🚫 upload(data) 실패(\(path)): code=\(ns.code) domain=\(ns.domain) desc=\(ns.localizedDescription)")
                    continuation.resume(throwing: StorageError.FailedToUploadImage)
                    return
                }
                continuation.resume(returning: path)
            }
            _ = task.observe(.progress) { snap in
                if let p = snap.progress {
                    progress?(p.completedUnitCount, p.totalUnitCount)
                }
            }
        }
    }

    /// Upload a local file URL to a Storage path with metadata (streaming; memory friendly).
    /// - Returns: the Storage path (same as `to`)
    @discardableResult
    func uploadFile(from fileURL: URL,
                    to path: String,
                    contentType: String,
                    cacheControl: String? = nil,
                    progress: ((Int64, Int64) -> Void)? = nil) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let ref = storage.reference().child(path)
            let meta = StorageMetadata()
            meta.contentType = contentType
            if let cc = cacheControl {
                meta.cacheControl = cc
            }
            let task = ref.putFile(from: fileURL, metadata: meta) { _, error in
                if let error = error {
                    let ns = error as NSError
                    print("🚫 uploadFile 실패(\(path)): code=\(ns.code) domain=\(ns.domain) desc=\(ns.localizedDescription)")
                    continuation.resume(throwing: StorageError.FailedToUploadImage)
                    return
                }
                continuation.resume(returning: path)
            }
            _ = task.observe(.progress) { snap in
                if let p = snap.progress {
                    progress?(p.completedUnitCount, p.totalUnitCount)
                }
            }
        }
    }

    // MARK: - Chat image attachment meta

    /// Message용(썸네일 + 원본) 일괄 업로드
    /// - Parameters:
    ///   - pairs: MediaManager.preparePairs(_:) 결과
    ///   - roomID, messageID: 저장 경로 구성에 사용
    ///   - cacheTTLThumbDays / cacheTTLOriginalDays: Cache-Control 설정 (일)
    ///   - cleanupTemp: 업로드 후 로컬 임시 원본 삭제 여부
    /// - Returns: 업로드된 첨부 메타 배열 (index 기준 정렬)
    func uploadPairsToRoomMessage(_ pairs: [MediaManager.ImagePair],
                                  roomID: String,
                                  messageID: String,
                                  cacheTTLThumbDays: Int = 30,
                                  cacheTTLOriginalDays: Int = 7,
                                  cleanupTemp: Bool = true,
                                  onProgress: ((Double) -> Void)? = nil) async throws -> [Attachment] {
        let thumbCC = "public, max-age=\(cacheTTLThumbDays * 24 * 3600)"
        let originCC = "public, max-age=\(cacheTTLOriginalDays * 24 * 3600)"

        // Aggregate progress: sum of all bytes (thumb + original) across pairs
        let totalBytes: Int64 = pairs.reduce(0) { partial, p in
            partial + Int64(p.thumbData.count) + Int64(p.bytesOriginal)
        }
        var uploadedBytes: Int64 = 0
        let progressQueue = DispatchQueue(label: "firebase.upload.progress.aggregate")
        var lastReported: [String: Int64] = [:]  // per-path last completed
        if totalBytes > 0 { onProgress?(0.0) }

        let limiter = AsyncSemaphore(4) // up to 4 uploads in parallel

        let (attachments, hadFailure) = await withTaskGroup(of: (Int, Attachment)?.self, returning: ([Attachment], Bool).self) { group in
            for p in pairs {
                group.addTask { [weak self] in
                    guard let self = self else { return nil }
                    await limiter.acquire()
                    defer { Task { await limiter.release() } }
                    let base = p.fileBaseName // sha256
                    let pathThumb = "rooms/\(roomID)/messages/\(messageID)/Thumb/\(base).jpg"
                    let pathOriginal = "rooms/\(roomID)/messages/\(messageID)/Original/\(base).jpg"

                    // Preflight: ensure original file URL is valid and non-empty
                    let fileURL = p.originalFileURL
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
                        _ = try await self.uploadWithRetry(
                            data: p.thumbData,
                            to: pathThumb,
                            contentType: "image/jpeg",
                            cacheControl: thumbCC,
                            progress: { completed, _ in
                                progressQueue.async {
                                    let prev = lastReported[pathThumb] ?? 0
                                    let delta = max(0, completed - prev)
                                    uploadedBytes += delta
                                    lastReported[pathThumb] = completed
                                    if totalBytes > 0 { onProgress?(Double(uploadedBytes) / Double(totalBytes)) }
                                }
                            })

                        // 2) 원본 업로드(File URL; 스트리밍) + 실패 시 putData 폴백
                        do {
                            _ = try await self.uploadFileWithRetry(
                                from: p.originalFileURL,
                                to: pathOriginal,
                                contentType: "image/jpeg",
                                cacheControl: originCC,
                                progress: { completed, _ in
                                    progressQueue.async {
                                        let prev = lastReported[pathOriginal] ?? 0
                                        let delta = max(0, completed - prev)
                                        uploadedBytes += delta
                                        lastReported[pathOriginal] = completed
                                        if totalBytes > 0 { onProgress?(Double(uploadedBytes) / Double(totalBytes)) }
                                    }
                                })
                        } catch {
                            let ns = error as NSError
                            let underlying = (ns.userInfo[NSUnderlyingErrorKey] as? NSError)
                            let uCode = underlying?.code ?? 0
                            let uDomain = underlying?.domain ?? ""
                            print("⚠️ uploadFile 실패, data 업로드로 폴백 시도 (path=\(pathOriginal)) code=\(ns.code)/\(ns.domain) underlying=\(uCode)/\(uDomain)")

                            if let size = self.fileSize(at: p.originalFileURL), size <= self.dataFallbackMaxBytes {
                                // Only one large putData fallback at a time to control memory spikes
                                await self.dataFallbackLimiter.acquire()
                                defer { Task { await self.dataFallbackLimiter.release() } }

                                guard let data = try? Data(contentsOf: p.originalFileURL, options: [.mappedIfSafe]) else {
                                    throw error
                                }

                                _ = try await self.uploadWithRetry(
                                    data: data,
                                    to: pathOriginal,
                                    contentType: "image/jpeg",
                                    cacheControl: originCC,
                                    progress: { completed, _ in
                                        progressQueue.async {
                                            let prev = lastReported[pathOriginal] ?? 0
                                            let delta = max(0, completed - prev)
                                            uploadedBytes += delta
                                            lastReported[pathOriginal] = completed
                                            if totalBytes > 0 { onProgress?(Double(uploadedBytes) / Double(totalBytes)) }
                                        }
                                    })
                                print("✅ 폴백 putData 업로드 성공(\(size) bytes ≤ limit=\(self.dataFallbackMaxBytes)): \(pathOriginal)")
                            } else {
                                // 폴백 불가 → 원래 오류 재throw
                                throw error
                            }
                        }

                        // 3) 로컬 임시 파일 정리 (성공 시에만)
                        if cleanupTemp { try? FileManager.default.removeItem(at: p.originalFileURL) }

                        let attachment = Attachment(
                            type: .image,
                            index: p.index,
                            pathThumb: pathThumb,
                            pathOriginal: pathOriginal,
                            width: p.originalWidth,
                            height: p.originalHeight,
                            bytesOriginal: p.bytesOriginal,
                            hash: p.sha256,
                            blurhash: nil
                        )
                        return (p.index, attachment)
                    } catch {
                        // 개별 실패는 여기서 소비하고 nil 반환 → 다른 작업은 cancel되지 않음
                        let ns = error as NSError
                        print("🚫 pair 업로드 실패 index=\(p.index) thumb=\(pathThumb) orig=\(pathOriginal) code=\(ns.code) domain=\(ns.domain) desc=\(ns.localizedDescription)")
                        return nil
                    }
                }
            }

            var ordered = Array<Attachment?>(repeating: nil, count: pairs.count)
            for await result in group {
                if let (idx, att) = result { ordered[idx] = att }
            }

            // 진행률 완료 표시
            if totalBytes > 0 { onProgress?(1.0) }

            let hadFailure = ordered.contains(where: { $0 == nil })
            return (ordered.compactMap { $0 }, hadFailure)
        }

        if hadFailure {
            throw StorageError.FailedToUploadImage
        }
        return attachments
    }

    @available(*, deprecated, message: "채팅용 이미지에는 사용하지 마세요. (UIImage 재인코딩) — 메시지 첨부는 MediaManager.preparePairs -> uploadPairsToRoomMessage를 사용하세요.")
    func uploadImageToStorage(image: UIImage, location: ImageLocation, roomName: String?) async throws -> String {
        let uuid = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "\(uuid)-\(timestamp).jpg"
        
        let imagePath: String
        switch location {
        case .ProfileImage:
            imagePath = "\(location.location)/\(fileName)"
        case .RoomImage:
            imagePath = "\(location.location)/\(roomName ?? "")/\(fileName)"
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let storageRef = storage.reference()
            let imageRef = storageRef.child(imagePath)
            
            guard let imageData = image.jpegData(compressionQuality: 0.5) else {
                print("이미지 데이터 생성 실패")
                continuation.resume(throwing: StorageError.FailedToConvertImage)
                return
            }
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            
            let uploadTask = imageRef.putData(imageData, metadata: metadata) { metadata, error in
                guard error == nil else {
                    continuation.resume(throwing: StorageError.FailedToUploadImage)
                    return
                }
                continuation.resume(returning: imagePath)
            }
            
            let _ = uploadTask.observe(.progress) { snapshot in
                let percentComplete = 100.0 * Double(snapshot.progress!.completedUnitCount) / Double(snapshot.progress!.totalUnitCount)
                print("Upload is \(percentComplete) done")
            }
        }
    }
    
    func uploadImagesToStorage(images: [UIImage], location: ImageLocation, name: String?) async throws -> [String] {
        let start = Date()
        
        return try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, image) in images.enumerated() {
                group.addTask {
                    
                    let fileName = try await self.uploadImageToStorage(image: image, location: location, roomName: name ?? "")
                    return (index, fileName)
                    
                }
            }
            
            var results = Array<String?>(repeating: nil, count: images.count)
            
            for try await (index, fileName) in group {
                results[index] = fileName
            }
                
            let end = Date()
            let duration = end.timeIntervalSince(start)
            let formattedTime = String(format: "%.2f", duration)
            print("⏱ 소요 시간: \(formattedTime)초")
            
            return results.compactMap{ $0 }
        }
    }
    
    func deleteImageFromStorage(path: String) {
        let fileRef = storage.reference().child("\(path)")
        print(#function, "📄 \(fileRef)")
        fileRef.delete { error in
            if let error = error {
                print("🚫 이미지 삭제 실패: \(error.localizedDescription)")
            } else {
                print("✅ 이미지 삭제 성공: \(path)")
                
                KingFisherCacheManager.shared.removeImage(forKey: path)
            }
        }
    }
    
//    func uploadVideoToStorage(_ videoURL: URL) async throws -> String {
//        let videoName = UUID().uuidString
//        let path = "videos/\(videoName).mp4"
//        let meta = StorageMetadata()
//        meta.contentType = "video/mp4"
//
//        return try await withCheckedThrowingContinuation { continuation in
//            let ref = storage.reference().child(path)
//            let task = ref.putFile(from: videoURL, metadata: meta) { _, error in
//                if let error = error {
//                    print("비디오 업로드 실패: \(error.localizedDescription)")
//                    continuation.resume(throwing: StorageError.FailedToUploadVideo)
//                    return
//                }
//                continuation.resume(returning: path)
//            }
//            _ = task.observe(.progress) { snapshot in
//                if let p = snapshot.progress {
//                    let percentComplete = 100.0 * Double(p.completedUnitCount) / Double(p.totalUnitCount)
//                    print("⬆️ video upload \(String(format: \"%.1f\", percentComplete))%")
//                }
//            }
//        }
//    }
    
//    func uploadVideosToStorage(_ videoURLs: [URL]) async throws -> [String] {
//        var videoNames = Array<String?>(repeating: nil, count: videoURLs.count)
//
//        for videoURL in videoURLs {
//            do {
//
//                let videoName = try await self.uploadVideoToStorage(videoURL)
//                videoNames.append(videoName)
//
//            } catch {
//
//                throw error
//
//            }
//        }
//
//        return videoNames.compactMap{$0}
//
//    }
    
    // Storage에서 이미지 불러오기
    func fetchImageFromStorage(image imagePath: String, location: ImageLocation/*, createdDate: Date*/) async throws -> UIImage {
        
        // 메모리 캐시 확인
        if let cachedImage = KingfisherManager.shared.cache.retrieveImageInMemoryCache(forKey: imagePath) {
            print("cachedImage in Memory: \(cachedImage)")
            
            return cachedImage
        }
        // 디스크 캐시 확인
        if let cachedImage = try await KingfisherManager.shared.cache.retrieveImageInDiskCache(forKey: imagePath) {
            print("cachedImage in Disk: \(cachedImage)")
            
            return cachedImage
        }
        
//        let month = DateManager.shared.getMonthFromTimestamp(date: createdDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let imageRef = storage.reference().child(imagePath)
            imageRef.getData(maxSize: 1 * 1024 * 1024) { data, error in
                if let error = error {
                    
                    print("\(imagePath): 이미지 불러오기 실패: \(error.localizedDescription)")
                    continuation.resume(throwing: StorageError.FailedToFetchImage)
                    
                }
                
                if let data = data,
                   let image = UIImage(data: data) {
                    
                    Task { try await KingfisherManager.shared.cache.store(image, forKey: imagePath) }
                    continuation.resume(returning: image)
                }
            }
        }
    }
    
    
    // Storage에서 여러 이미지 불러오는 함수
    func fetchImagesFromStorage(from imagePaths: [String], location: ImageLocation, createdDate: Date) async throws -> [UIImage] {
        
        var images = Array<UIImage?>(repeating: nil, count: imagePaths.count)
        
        try await withThrowingTaskGroup(of: (Int, UIImage).self, returning: Void.self) { group in
            for (index, imagePath) in imagePaths.enumerated() {
                group.addTask {
                    
                    let image = try await self.fetchImageFromStorage(image: imagePath, location: location/*, createdDate: createdDate*/)
                    return (index, image)
                    
                }
            }
            for try await (index, image) in group {
                images[index] = image
            }
        }
        
        return images.compactMap { $0 }
    }
    
    // Preload (warm) cache for multiple Storage image paths without holding images in memory
    func prefetchImages(paths: [String], location: ImageLocation, createdDate: Date = Date()) {
        Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                // We reuse the existing parallel downloader which also stores to Kingfisher cache.
                _ = try await self.fetchImagesFromStorage(from: paths, location: location, createdDate: createdDate)
            } catch {
                print("⚠️ warmImageCache 실패: \(error)")
            }
        }
    }
}
