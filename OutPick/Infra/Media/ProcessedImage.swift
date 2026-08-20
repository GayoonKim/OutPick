//
//  ProcessedImage.swift
//  OutPick
//
//  Created by Codex on 6/24/26.
//

import Foundation

/// 이미지 업로드/전송을 위한 공용 가공 결과 모델.
struct ProcessedImage: Sendable {
    let index: Int

    /// 앱이 소유한 임시 폴더로 복사된 원본 파일 URL.
    let originalFileURL: URL

    /// 전송/캐시용 썸네일 JPEG 데이터.
    let thumbData: Data

    /// 원본 픽셀 크기.
    let originalWidth: Int
    let originalHeight: Int

    /// 원본 파일 크기(bytes).
    let bytesOriginal: Int

    /// 파일 내용 기반 SHA-256.
    let sha256: String

    /// Quarantine transport source의 실제 MIME과 표시 형식.
    let contentType: String
    let mediaFormat: String
    let isAnimated: Bool

    init(
        index: Int,
        originalFileURL: URL,
        thumbData: Data,
        originalWidth: Int,
        originalHeight: Int,
        bytesOriginal: Int,
        sha256: String,
        contentType: String = "image/jpeg",
        mediaFormat: String = "jpeg",
        isAnimated: Bool = false
    ) {
        self.index = index
        self.originalFileURL = originalFileURL
        self.thumbData = thumbData
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
        self.bytesOriginal = bytesOriginal
        self.sha256 = sha256
        self.contentType = contentType
        self.mediaFormat = mediaFormat
        self.isAnimated = isAnimated
    }

    /// Storage/cache key로 쓰는 base name.
    var fileBaseName: String { sha256 }
}
