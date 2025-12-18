//
//  Media.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

// MARK: - 미디어 (사진/영상 확장성 고려)
enum MediaType: String, Codable { case image, video }

struct MediaAsset: Equatable, Codable {
    let type: MediaType
    let url: URL            // 다운로드 URL (또는 CDN URL)
    let thumbnailURL: URL?  // 성능용 썸네일
//    let width: Int?
//    let height: Int?
}
