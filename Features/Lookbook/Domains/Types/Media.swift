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

struct CommentAttachment: Equatable, Codable, Identifiable {
    let id: String
    let type: MediaType
    let remoteURL: URL?
    let thumbPath: String?
    let detailPath: String?
    let originalPath: String?

    /// 댓글 목록과 댓글 시트에서 먼저 시도할 Storage 경로
    var preferredListPath: String? {
        thumbPath ?? detailPath ?? originalPath
    }

    /// 첨부 확대 화면에서 먼저 보여줄 Storage 경로
    var preferredPreviewPath: String? {
        thumbPath ?? detailPath ?? originalPath
    }

    /// 첨부 확대 화면에서 백그라운드로 교체할 원본 후보 경로
    var preferredOriginalPath: String? {
        originalPath ?? detailPath ?? thumbPath
    }
}
