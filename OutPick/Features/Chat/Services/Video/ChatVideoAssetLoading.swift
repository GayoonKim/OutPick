//
//  ChatVideoAssetLoading.swift
//  OutPick
//
//  Created by Codex on 6/23/26.
//

import Foundation

protocol ChatVideoAssetLoading {
    func cacheVideoAssetsIfNeeded(
        for message: ChatMessage,
        maxThumbnailBytes: Int
    ) async

    func prefetchVideoAssets(
        for messages: [ChatMessage],
        maxThumbnailBytes: Int,
        maxConcurrent: Int
    ) async
}
