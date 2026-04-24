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
    let remoteURL: URL
    let thumbPath: String?
    let detailPath: String?
    let sourcePageURL: URL?

    /// 목록/그리드에서 먼저 시도할 Storage 경로
    var preferredListPath: String? {
        thumbPath ?? detailPath
    }

    /// 상세 화면에서 먼저 시도할 Storage 경로
    var preferredDetailPath: String? {
        detailPath ?? thumbPath
    }
}
