//
//  ChatStoragePath.swift
//  OutPick
//
//  Created by Codex on 3/27/26.
//

import Foundation

enum ChatStoragePath {
    struct ImagePaths: Sendable {
        let thumb: String
        let original: String
    }

    struct VideoPaths: Sendable {
        let video: String
        let thumb: String
    }

    static func roomCover(roomID: String, fileBaseName: String, fileExtension: String = "jpg") -> ImagePaths {
        ImagePaths(
            thumb: "rooms/\(roomID)/cover/thumb/\(fileBaseName).\(fileExtension)",
            original: "rooms/\(roomID)/cover/original/\(fileBaseName).\(fileExtension)"
        )
    }

    static func roomMessageImage(
        roomID: String,
        messageID: String,
        fileBaseName: String,
        fileExtension: String = "jpg"
    ) -> ImagePaths {
        let basePath = "rooms/\(roomID)/messages/\(messageID)/images/\(fileBaseName)"
        return ImagePaths(
            thumb: "\(basePath)/thumb.\(fileExtension)",
            original: "\(basePath)/original.\(fileExtension)"
        )
    }

    static func roomMessageVideo(
        roomID: String,
        messageID: String,
        videoFileName: String = "video.mp4",
        thumbFileName: String = "thumb.jpg"
    ) -> VideoPaths {
        let basePath = "rooms/\(roomID)/messages/\(messageID)/video"
        return VideoPaths(
            video: "\(basePath)/\(videoFileName)",
            thumb: "\(basePath)/\(thumbFileName)"
        )
    }
}
