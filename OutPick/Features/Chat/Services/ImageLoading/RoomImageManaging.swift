//
//  RoomImageManaging.swift
//  OutPick
//
//  Created by Codex on 3/24/26.
//

import Foundation
import UIKit

protocol RoomImageManaging {
    func cachedImage(for path: String) async -> UIImage?
    func loadImage(for path: String, maxBytes: Int) async throws -> UIImage
    func prefetchImages(paths: [String], maxBytes: Int, maxConcurrent: Int) async
    func storeImageDataToCache(_ data: Data, for path: String) async throws
    func removeCachedImage(for path: String) async
}
