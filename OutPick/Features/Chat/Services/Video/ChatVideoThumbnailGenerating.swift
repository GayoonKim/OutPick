//
//  ChatVideoThumbnailGenerating.swift
//  OutPick
//
//  Created by Codex on 6/23/26.
//

import Foundation
import UIKit

protocol ChatVideoThumbnailGenerating {
    func thumbnailData(url: URL, maxPixel: CGFloat) async throws -> Data
}
