//
//  PreparedVideo.swift
//  OutPick
//
//  채팅 전송을 위한 비디오 가공 결과 모델
//

import Foundation

struct PreparedVideo {
    let compressedFileURL: URL
    let thumbnailData: Data
    let sha256: String
    let duration: Double
    let width: Int
    let height: Int
    let sizeBytes: Int64
    let approxBitrateMbps: Double
    let preset: DefaultMediaProcessingService.VideoUploadPreset
}
