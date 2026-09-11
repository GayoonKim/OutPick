import Foundation

/// 사진 파일 제한은 MB(10진 바이트)로 통일한다. 묶음 합산에는 본 파일만 포함한다.
enum ChatPhotoSizePolicy {
    static let maximumFileBytes = 300_000_000
    static let maximumBatchDisplayBytes = 300_000_000
    static let maximumImagesPerMessage = 30

    static func acceptsFile(bytes: Int) -> Bool {
        bytes > 0 && bytes <= maximumFileBytes
    }
}
