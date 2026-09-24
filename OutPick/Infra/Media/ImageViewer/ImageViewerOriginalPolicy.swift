import Foundation
import ImageIO
import UIKit

enum ImageViewerOriginalPolicy {
    static func indices(pages: [ImageViewerPage], current: Int) -> Set<Int> {
        guard pages.indices.contains(current) else { return [] }
        var result: Set<Int> = [current]
        for index in [current - 1, current + 1] where pages.indices.contains(index) {
            guard !pages[index].isAnimated else { continue }
            // 사진 전용 뷰어에서 제외된 영상 첨부를 넘어 선로딩하지 않는다.
            if let position = pages[current].attachmentPosition, let adjacent = pages[index].attachmentPosition,
               abs(position - adjacent) != 1 { continue }
            result.insert(index)
        }
        return result
    }
}

enum ImageViewerOriginalDecoder {
    static func image(fileURL: URL, animated: Bool) async -> UIImage? {
        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard !Task.isCancelled else { return nil }
            if animated {
                guard let data = try? Data(contentsOf: fileURL, options: [.alwaysMapped]) else { return nil }
                return SimpleImageViewerVC.makeAnimatedImage(from: data)
            }
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 4096,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: image)
        }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
}
