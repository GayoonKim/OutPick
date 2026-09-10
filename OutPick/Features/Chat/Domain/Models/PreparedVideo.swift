//
//  PreparedVideo.swift
//  OutPick
//
//  채팅 전송을 위한 비디오 가공 결과 모델
//

import Foundation

struct PreparedVideo {
    let compressedFileURL: URL
    private let inlineThumbnailData: Data
    let thumbnailFileURL: URL?
    var thumbnailData: Data { thumbnailFileURL.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) } ?? inlineThumbnailData }
    let sha256: String
    let duration: Double
    let width: Int
    let height: Int
    let sizeBytes: Int64
    let approxBitrateMbps: Double
    let preset: VideoUploadPreset
    let preparationVersion: Int

    init(compressedFileURL: URL, thumbnailData: Data, sha256: String, duration: Double,
         width: Int, height: Int, sizeBytes: Int64, approxBitrateMbps: Double,
         preset: VideoUploadPreset, thumbnailFileURL: URL? = nil, preparationVersion: Int = 3) {
        self.compressedFileURL = compressedFileURL
        self.inlineThumbnailData = thumbnailData
        self.thumbnailFileURL = thumbnailFileURL
        self.sha256 = sha256
        self.duration = duration
        self.width = width
        self.height = height
        self.sizeBytes = sizeBytes
        self.approxBitrateMbps = approxBitrateMbps
        self.preset = preset
        self.preparationVersion = preparationVersion
    }
}
