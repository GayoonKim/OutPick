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

enum ImageType: String, CaseIterable {
    case ProfileImage
    case RoomImage
    case Test
    
    var type: String {
        switch self {
            
        case .ProfileImage:
            "Profile_Images"
            
        case .RoomImage:
            "Room_Images"
            
        case .Test:
            "Test"
            
        }
    }
}
    
class FirebaseStorageManager {
    
    static let shared = FirebaseStorageManager()
    
    // Firestore 인스턴스
    let db = Firestore.firestore()
    
    // Storage 인스턴스
    let storage = Storage.storage()
    
    
    func uploadImageToStorage(image: UIImage, type: ImageType) async throws -> String {
        
        let imageName = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
        
            let storageRef = storage.reference()
            let imageRef = storageRef.child("\(type.type)/\(imageName).jpg")
            
            let reszied = image.resized(withMaxWidth: 700)
            
            guard let imageData = reszied.jpegData(compressionQuality: 0.5) else {
                print("이미지 데이터 생성 실패")
                return
            }
            
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            
            let uploadTask = imageRef.putData(imageData, metadata: nil) { metadata, error in
                if let error = error {
                    
                    continuation.resume(throwing: error)
                    return
                    
                }
            }
            
            let _ = uploadTask.observe(.progress) { snapshot in

                let percentComplete = 100.0 * Double(snapshot.progress!.completedUnitCount) / Double(snapshot.progress!.totalUnitCount)
                print("Upload is \(percentComplete) done")
                
            }
            
            continuation.resume(returning: imageName)
            
        }
        
    }
    
    func uploadImagesToStorage(images: [UIImage], type: ImageType) async throws -> [String] {
        
        var resultNames = Array<String?>(repeating: nil, count: images.count)
        
        for image in images {
            do {
                
                let imageName = try await uploadImageToStorage(image: image, type: type)
                resultNames.append(imageName)
                
            } catch {
                
                throw error
                
            }
        }
        
        return resultNames.compactMap{$0}
        
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
                
                let percentComplete = 100.0 * Double(snapshot.progress!.completedUnitCount) / Double(snapshot.progress!.totalUnitCount)
                print("Upload is \(percentComplete) done")
                
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
    func fetchImageFromStorage(image imageName: String, type: ImageType) async throws -> UIImage {
        
        // 메모리 캐시 확인
        if let cachedImage = KingfisherManager.shared.cache.retrieveImageInMemoryCache(forKey: imageName) {
            print("cachedImage: \(cachedImage)")
            return cachedImage
        }
        // 디스크 캐시 확인
        if let cachedImage = try await KingfisherManager.shared.cache.retrieveImageInDiskCache(forKey: imageName) {
            print("cachedImage: \(cachedImage)")
            return cachedImage
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let imageRef = storage.reference().child("\(type)/\(imageName).jpg")
            imageRef.getData(maxSize: 1 * 1024 * 1024) { data, error in
                if let error = error {
                    
                    print("\(imageName): 이미지 불러오기 실패: \(error.localizedDescription)")
                    
                }
                    
                if let data = data,
                   let image = UIImage(data: data) {
                 
                    KingfisherManager.shared.cache.store(image, forKey: imageName)
                    continuation.resume(returning: image)
                    
                }
            }
        }
    }
    

    // Storage에서 여러 이미지 불러오는 함수
    func fetchImagesFromStorage(from imageNames: [String], type: ImageType) async throws -> [UIImage] {
        
        var images = Array<UIImage?>(repeating: nil, count: imageNames.count)
        
        try await withThrowingTaskGroup(of: (Int, UIImage).self, returning: Void.self) { group in
            for (index, imageName) in imageNames.enumerated() {
                group.addTask {
                    
                    let image = try await self.fetchImageFromStorage(image: imageName, type: type)
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
