import Foundation

enum ChatMediaSelectionChunker {
    static let maxImagesPerMessage = 30
    static let maxAggregateBytes = 150 * 1024 * 1024

    static func chunks(_ images: [ProcessedImage]) -> [[ProcessedImage]] {
        var result: [[ProcessedImage]] = []
        var current: [ProcessedImage] = []
        var currentBytes = 0
        for image in images.sorted(by: { $0.index < $1.index }) {
            let wouldExceedCount = current.count >= maxImagesPerMessage
            let wouldExceedBytes = !current.isEmpty && currentBytes + image.bytesOriginal > maxAggregateBytes
            if wouldExceedCount || wouldExceedBytes {
                result.append(reindexed(current))
                current = []
                currentBytes = 0
            }
            current.append(image)
            currentBytes += image.bytesOriginal
        }
        if !current.isEmpty { result.append(reindexed(current)) }
        return result
    }

    private static func reindexed(_ images: [ProcessedImage]) -> [ProcessedImage] {
        images.enumerated().map { index, image in
            ProcessedImage(
                index: index,
                originalFileURL: image.originalFileURL,
                thumbData: image.thumbData,
                originalWidth: image.originalWidth,
                originalHeight: image.originalHeight,
                bytesOriginal: image.bytesOriginal,
                sha256: image.sha256,
                contentType: image.contentType,
                mediaFormat: image.mediaFormat,
                isAnimated: image.isAnimated
            )
        }
    }
}
