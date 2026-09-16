import Foundation
import UIKit
import ImageIO

/// 파일 소유권은 디코딩·비동기 캐시 저장이 끝날 때까지 전달한다.
final class ImageTemporaryFile: @unchecked Sendable {
    let url: URL
    init() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("outpick-image-loading", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(UUID().uuidString)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}

enum ImageCachePayload: Sendable {
    case data(Data)
    case file(ImageTemporaryFile)
}

enum ImageFileDecoding {
    static func image(_ url: URL) -> UIImage? {
        // 픽셀 크기를 줄이지 않는다. 기존 파일의 orientation을 UIImage가 해석한다.
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        return image.preparingForDisplay() ?? image
    }
    static func image(_ data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        return image.preparingForDisplay() ?? image
    }
}
