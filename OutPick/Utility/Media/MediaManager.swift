//
//  MediaManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/10/25.
//

import UIKit
import PhotosUI
import ImageIO

class MediaManager {
    
    static let shared = MediaManager()
    
    func convertImage(_ result: PHPickerResult) async throws -> UIImage {
        
        return try await withCheckedThrowingContinuation { continuation in
            let itemProvider = result.itemProvider
            if itemProvider.canLoadObject(ofClass: UIImage.self) {
                itemProvider.loadObject(ofClass: UIImage.self, completionHandler: { [weak itemProvider] image, error in
                    
                    guard let image = image as? UIImage, error == nil else {
                        continuation.resume(throwing: MediaError.FailedToConvertImage)
                        return
                    }
                    
                    let options: [NSString:Any] = [
                        kCGImageSourceThumbnailMaxPixelSize: 500,
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true
                    ]
                    
                    guard let imageData = image.jpegData(compressionQuality: 0.5),
                          let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
                          let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                        
                        print("압축 이미지 데이터 생성 실패")
                        continuation.resume(throwing: MediaError.FailedToCraeteImageData)
                        return
                    }
                    
                    continuation.resume(returning: UIImage(cgImage: cgImage))
                    
                })
            }
        }
        
    }
    
    func dealWithImages(_ results: [PHPickerResult]) async throws -> [UIImage] {
        
        var images = Array<UIImage?>(repeating: nil, count: results.count)
        
        for result in results {
            do {
                
                let image = try await convertImage(result)
                images.append(image)
                
            } catch {
                
                throw error
                
            }
        }
        
        return images.compactMap{$0}
        
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
                    
                    VideoCompressor.compressVideo(inputURL: fileURL) { result in
                        switch result {
                        case .success(let outputURL):
                            continuation.resume(returning: outputURL)
                            
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

class VideoCompressor {
    
    static func compressVideo(inputURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("compressed_\(UUID().uuidString).mp4")
        
        // 기존 압축 파일이 있다면 삭제
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        let asset = AVAsset(url: inputURL)
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset640x480) else {
            completion(.failure(NSError(domain: "CompressError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export session could not be created."])))
            return
        }
        
        exportSession.shouldOptimizeForNetworkUse = true
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        
        exportSession.exportAsynchronously {
            switch exportSession.status {
                
            case .completed:
                completion(.success(outputURL))
            case .failed:
                completion(.failure(exportSession.error ?? NSError(domain: "VideoCompression", code: -1, userInfo: [NSLocalizedDescriptionKey: "알 수 없는 에러"])))
            case .cancelled:
                completion(.failure(NSError(domain: "VideoCompression", code: -1, userInfo: [NSLocalizedDescriptionKey: "압축 작업 취소"])))
            default:
                completion(.failure(NSError(domain: "VideoCompression", code: -1, userInfo: [NSLocalizedDescriptionKey: "알 수 없는 에러"])))
            }
        }
        
    }
    
}
