//
//  ChatAvatarImageManaging.swift
//  OutPick
//
//  Created by Codex on 3/24/26.
//

import Foundation
import UIKit

protocol ChatAvatarImageManaging {
    func cachedAvatar(for path: String) async -> UIImage?
    func loadAvatar(for path: String, maxBytes: Int) async throws -> UIImage
    func prefetchAvatars(paths: [String], maxBytes: Int, maxConcurrent: Int) async
    func storeAvatarDataToCache(_ data: Data, for path: String) async throws
    func removeCachedAvatar(for path: String) async
}
