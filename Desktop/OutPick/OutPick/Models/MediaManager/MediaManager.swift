//
//  MediaManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/10/25.
//

import UIKit
import PhotosUI
import ImageIO
import FYVideoCompressor

class MediaManager {
    
    static let shared = MediaManager()
    
    static func compressImageWithImageIO(_ image: UIImage) -> CGImage?{
        let options: [NSString:Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 500,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        
        guard let imageData = image.jpegData(compressionQuality: 0.5),
              let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            
            print("압축 이미지 데이터 생성 실패")
            return nil
        }
        
        return cgImage
    }
    
    func convertImage(_ result: PHPickerResult) async throws -> UIImage {
        return try await withCheckedThrowingContinuation { continuation in
            let itemProvider = result.itemProvider
            if itemProvider.canLoadObject(ofClass: UIImage.self) {
                itemProvider.loadObject(ofClass: UIImage.self, completionHandler: { image, error in
                    guard let image = image as? UIImage, error == nil else {
                        continuation.resume(throwing: MediaError.FailedToConvertImage)
                        return
                    }

                    guard let compressed = MediaManager.compressImageWithImageIO(image) else {
                        print("압축 이미지 데이터 생성 실패")
                        continuation.resume(throwing: MediaError.FailedToCraeteImageData)
                        return
                    }
                    
                    continuation.resume(returning: UIImage(cgImage: compressed))
                })
            }
        }
    }
    
    func dealWithImages(_ results: [PHPickerResult]) async throws -> [UIImage] {
        return try await withThrowingTaskGroup(of: (Int, UIImage).self) { group in
            for (index, result) in results.enumerated() {
                group.addTask {
                    let image = try await self.convertImage(result)
                    return (index, image)
                }
            }
            
            var inOrderImages = Array<UIImage?>(repeating: nil, count: results.count)
            for try await (index, image) in group {
                inOrderImages[index] = image
            }
            return inOrderImages.compactMap{$0}
        }
    }
    
    func convertVideo(_ result: PHPickerResult) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let itemProvider = result.itemProvider
            if itemProvider.hasRepresentationConforming(toTypeIdentifier: UTType.movie.identifier) {
                itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { fileURL, error in
                    guard let fileURL = fileURL, error == nil else {
                        continuation.resume(throwing: error ?? NSError(domain: "VideoLoad", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video URL 불러오기 실패"]))
                        return
                    }
                    
                    let config = FYVideoCompressor.CompressionConfig(videoBitrate: 2000_000, videomaxKeyFrameInterval: 10, fps: 30, audioSampleRate: 44100, audioBitrate: 128_000, fileType: .mp4, scale: CGSize(width: 1280, height: 720))
                    
                    FYVideoCompressor().compressVideo(fileURL, config: config) { result in
                        switch result {
                            
                        case .success(let compressedVideoURL):
                            continuation.resume(returning: compressedVideoURL)
                            
                        case .failure(let error):
                            continuation.resume(throwing: error)
                            
                        }
                    }
                    
                }
            }
        }
    }
    
    func dealWithVideos(_ results: [PHPickerResult]) async throws -> [URL] {
        
        var compressedURLs = Array<URL?>(repeating: nil, count: results.count)
        
        for result in results {
            do {
                
                let compressedURL = try await convertVideo(result)
                compressedURLs.append(compressedURL)
                
            } catch {
                
                print("PHPicker에서 불러온 동영상 변환 실패: \(error)")
                
            }
        }
        
        return compressedURLs.compactMap{$0}
        
    }
    
}
