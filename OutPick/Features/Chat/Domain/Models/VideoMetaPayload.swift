//
//  VideoMetaPayload.swift
//  OutPick
//
//  Created by Codex on 6/16/26.
//

import Foundation

struct VideoMetaPayload: Codable, Sendable {
    let roomID: String
    let messageID: String
    let storagePath: String      // "rooms/<room>/messages/<msg>/video/video.mp4"
    let thumbnailPath: String    // "rooms/<room>/messages/<msg>/video/thumb.jpg"
    let duration: Double
    let width: Int
    let height: Int
    let sizeBytes: Int64
    let approxBitrateMbps: Double
    let preset: String           // "standard720" | "dataSaver720" | "high1080"
}
