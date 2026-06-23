//
//  DefaultChatVideoThumbnailGenerator.swift
//  OutPick
//
//  Created by Codex on 6/23/26.
//

import AVFoundation
import Foundation
import UIKit

final class DefaultChatVideoThumbnailGenerator: ChatVideoThumbnailGenerating {
    func thumbnailData(url: URL, maxPixel: CGFloat) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            let image = UIImage(cgImage: cgImage)
            let scaled = image.resizeMaxPixel(maxPixel)
            return scaled.jpegData(compressionQuality: 0.8) ?? Data()
        }.value
    }
}

private extension UIImage {
    func resizeMaxPixel(_ maxPixel: CGFloat) -> UIImage {
        guard maxPixel > 0 else { return self }
        let width = size.width
        let height = size.height
        guard width > 0, height > 0 else { return self }
        let longSide = max(width, height)
        guard longSide > maxPixel else { return self }

        let scaleRatio = maxPixel / longSide
        var newWidth = floor(width * scaleRatio)
        var newHeight = floor(height * scaleRatio)
        newWidth = max(2, floor(newWidth / 2) * 2)
        newHeight = max(2, floor(newHeight / 2) * 2)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: newWidth, height: newHeight),
            format: format
        )
        return renderer.image { _ in
            self.draw(in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        }
    }
}
