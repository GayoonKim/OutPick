//
//  ImageThumbnailDataMaker.swift
//  OutPick
//
//  Created by Codex on 6/24/26.
//

import ImageIO
import UIKit

/// 이미지 소스로부터 JPEG thumbnail data를 생성하는 순수 utility.
enum ImageThumbnailDataMaker {
    static let defaultMaxPixel: Int = 500
    static let defaultQuality: CGFloat = 0.5

    static func makeData(
        from image: UIImage,
        maxPixel: Int = defaultMaxPixel,
        quality: CGFloat = defaultQuality
    ) -> Data? {
        guard let imageData = image.jpegData(compressionQuality: 1.0),
              let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return nil
        }
        return makeData(from: source, maxPixel: maxPixel, quality: quality)
    }

    static func makeData(
        from url: URL,
        maxPixel: Int = defaultMaxPixel,
        quality: CGFloat = defaultQuality
    ) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return makeData(from: source, maxPixel: maxPixel, quality: quality)
    }

    static func makeData(
        from source: CGImageSource,
        maxPixel: Int = defaultMaxPixel,
        quality: CGFloat = defaultQuality
    ) -> Data? {
        let options: [NSString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgThumb).jpegData(compressionQuality: quality)
    }
}
