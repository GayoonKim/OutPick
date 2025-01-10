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
    
class FirebaseMediaManager {
    
    static let shared = FirebaseMediaManager()
    
    // Firestore 인스턴스
    let db = Firestore.firestore()
    
    // Storage 인스턴스
    let storage = Storage.storage()
    
    
    func uploadImageToStorage(image: UIImage, type: String) async throws -> URL {
        
        return try await withCheckedThrowingContinuation { continuation in
        
            let storageRef = storage.reference()
            let imageRef = storageRef.child("\(type)/\(UUID().uuidString).jpg")
            
            let reszied = image.resized(withMaxWidth: 700)
            
            guard let imageData = reszied.jpegData(compressionQuality: 0.4) else {
                print("이미지 데이터 생성 실패")
                return
            }
            
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            
            let uploadTask = imageRef.putData(imageData, metadata: metadata) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                imageRef.downloadURL { imageURL, error in
                    
                    if let error = error {
                        print("이미지 업로드 실패: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    }
                        
                    if let imageURL = imageURL {
                        continuation.resume(returning: imageURL)
                    }
                    
                }
            }
            
            let _ = uploadTask.observe(.progress) { snapshot in

                guard let count = snapshot.progress?.completedUnitCount else { return }
                
                
            }
            
        }
        
    }
    
    func uploadImagesToStorage(_ images: [UIImage]) async throws -> [URL] {
        
        var resultURLs = Array<URL?>(repeating: nil, count: images.count)
        
        for image in images {
            do {
                
                let url = try await uploadImageToStorage(image: image, type: "test")
                resultURLs.append(url)
                
            } catch {
                
                throw error
                
            }
        }
        
        return resultURLs.compactMap{$0}
        
    }
    
    func uploadVideoToStorage(_ videoURL: URL) async throws -> URL {
        
        return try await withCheckedThrowingContinuation { continuation in
            
            guard let videoData = try? Data(contentsOf: videoURL) else {
                print("비디오 데이터 생성 실패")
                return
            }
            
            let videoRef = storage.reference().child("videos/\(UUID().uuidString).mp4")

            let uploadTask = videoRef.putData(videoData) { (metaData, error) in
            
                if let error = error {
                    print("비디오 업로드 실패: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                
                videoRef.downloadURL { downloadURL, error in
                    
                    if let error = error {
                        continuation.resume(throwing: error)
                    }
                        
                    if let downloadURL = downloadURL {
                        try? FileManager.default.removeItem(at: videoURL)
                        continuation.resume(returning: downloadURL)
                    }
                    
                }
                
            }
            
            let _ = uploadTask.observe(.progress) { snapshot in

                guard let count = snapshot.progress?.completedUnitCount else { return }
                
            }
            
        }
        
    }
    
    func uploadVideosToStorage(_ videoURLs: [URL]) async throws -> [URL] {
        
        var resultURLs = Array<URL?>(repeating: nil, count: videoURLs.count)
        
        for videoURL in videoURLs {
            do {
                
                let url = try await self.uploadVideoToStorage(videoURL)
                resultURLs.append(url)
                
            } catch {
                
                throw error
                
            }
        }
        
        return resultURLs.compactMap{$0}
        
    }
    
    
    // Storage에서 이미지 불러오기
    func fetchImageFromStorage(url: String/*, completion: @escaping (UIImage?) -> Void*/) async throws -> UIImage {
        
        // 메모리 캐시 확인
        if let cachedImage = KingfisherManager.shared.cache.retrieveImageInMemoryCache(forKey: url) {
            print("cachedImage: \(cachedImage)")
            return cachedImage
        }
        // 디스크 캐시 확인
        if let cachedImage = try await KingfisherManager.shared.cache.retrieveImageInDiskCache(forKey: url) {
            print("cachedImage: \(cachedImage)")
            return cachedImage
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            AF.request(url).responseData { response in
                
                switch response.result {
                case .success(let data):
                    // 작업 성공
                    guard let image = UIImage(data: data) else { return }
                    KingfisherManager.shared.cache.store(image, forKey: url)
                    continuation.resume(returning: image)
                case .failure(let error):
                    // 에러 발생
                    continuation.resume(throwing: error)
                }
                
            }
        }
        
    }
    
    func fetchImagesFromStorage(from urls: [String]) async throws -> [UIImage] {
        
        var images = Array<UIImage?>(repeating: nil, count: urls.count)
        
        try await withThrowingTaskGroup(of: (Int, UIImage).self, returning: Void.self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    
                    let image = try await self.fetchImageFromStorage(url: url)
                    return (index, image)
                    
                }
            }
            
            for try await (index, image) in group {
                
                images[index] = image
                
            }
            
        }
        
        return images.compactMap { $0 }
        
    }
    
}
