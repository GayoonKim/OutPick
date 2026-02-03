//
//  ChatMediaManagerProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import UIKit

/// 미디어(이미지/비디오) 캐싱 및 프리페치 관련 프로토콜
protocol ChatMediaManagerProtocol {
    var messageImages: [String: [UIImage]] { get set }
    
    /// 이미지 캐싱
    func cacheImagesIfNeeded(for message: ChatMessage) async -> [UIImage]
    
    /// 비디오 에셋 캐싱
    func cacheVideoAssetsIfNeeded(for message: ChatMessage, in roomID: String) async
    
    /// 이미지 썸네일 프리페치
    func prefetchThumbnails(for messages: [ChatMessage], maxConcurrent: Int) async
    
    /// 비디오 에셋 프리페치
    func prefetchVideoAssets(for messages: [ChatMessage], maxConcurrent: Int, roomID: String) async
    
    /// 이미지 뷰어용 URL 해석
    func resolveURLs(for paths: [String], concurrent: Int) async -> [URL]
    
    /// 단일 Storage 경로의 URL 해석
    func resolveURL(for path: String) async throws -> URL
    
    /// 비디오 업로드 및 브로드캐스트
    func uploadCompressedVideoAndBroadcast(roomID: String, compressedURL: URL, preset: MediaManager.VideoUploadPreset, hud: CircularProgressHUD?) async
    
    /// 비디오 썸네일 데이터 생성
    func makeVideoThumbnailData(url: URL, maxPixel: CGFloat) throws -> Data
    
    /// Storage 경로로 비디오 재생
    func playVideoForStoragePath(_ storagePath: String, in viewController: UIViewController) async
    
    /// 저장용 로컬 파일 URL 해석
    func resolveLocalFileURLForSaving(localURL: URL?, storagePath: String?, onProgress: @escaping (Double)->Void) async throws -> URL
}

