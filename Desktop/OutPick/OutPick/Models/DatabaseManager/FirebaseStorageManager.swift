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

class FirebaseStorageManager {
    
    static let shared = FirebaseStorageManager()
    
    // Firestore 인스턴스
    let db = Firestore.firestore()
    
    // Storage 인스턴스
    let storage = Storage.storage()
    
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
                    
                    let imagePath = try await self.uploadImageToStorage(image: image, location: location, roomName: name ?? "")
                    return (index, imagePath)
                    
                }
            }
            
            var resultPaths = Array<String?>(repeating: nil, count: images.count)
            
            for try await (index, imagePath) in group {
                resultPaths[index] = imagePath
            }
                
            let end = Date()
            let duration = end.timeIntervalSince(start)
            let formattedTime = String(format: "%.2f", duration)
            print("⏱ 소요 시간: \(formattedTime)초")
            
            return resultPaths.compactMap{ $0 }
        }
    }
    
    func deleteImageFromStorage(path: String) {
        let fileRef = storage.reference().child("\(path)")
        
        fileRef.delete { error in
            if let error = error {
                print("🚫 이미지 삭제 실패: \(error.localizedDescription)")
            } else {
                print("✅ 이미지 삭제 성공: \(path)")
                
                KingFisherCacheManager.shared.removeImage(forKey: path)
            }
        }
    }
    
    func uploadVideoToStorage(_ videoURL: URL) async throws -> String {
        let videoName = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
            
            guard let videoData = try? Data(contentsOf: videoURL) else {
                print("비디오 데이터 생성 실패")
                return
            }
            
            let videoRef = storage.reference().child("videos/\(videoName).mp4")
            
            let uploadTask = videoRef.putData(videoData) { (metaData, error) in
                if let error = error {
                    
                    print("비디오 업로드 실패: \(error.localizedDescription)")
                    continuation.resume(throwing: StorageError.FailedToUploadVideo)
                    return
                    
                }
                
            }
            
            let _ = uploadTask.observe(.progress) { snapshot in
        
                let percentComplete = 100.0 * Double(snapshot.progress!.completedUnitCount) / Double(snapshot.progress!.totalUnitCount)
                print("Upload is \(percentComplete) done")
                
            }
            
            continuation.resume(returning: videoName)
        }
    }
    
    func uploadVideosToStorage(_ videoURLs: [URL]) async throws -> [String] {
        var videoNames = Array<String?>(repeating: nil, count: videoURLs.count)
        
        for videoURL in videoURLs {
            do {
                
                let videoName = try await self.uploadVideoToStorage(videoURL)
                videoNames.append(videoName)
                
            } catch {
                
                throw error
                
            }
        }
        
        return videoNames.compactMap{$0}
        
    }
    
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
