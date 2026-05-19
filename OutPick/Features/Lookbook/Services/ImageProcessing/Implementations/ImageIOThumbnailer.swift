//
//  ImageIOThumbnailer.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

struct ImageIOThumbnailer: ImageThumbnailing {

    func makeThumbnailJPEGData(from originalJPEGData: Data, policy: ThumbnailPolicy) throws -> Data {

        let cfData = originalJPEGData as CFData
        guard let source = CGImageSourceCreateWithData(cfData, nil) else {
            throw NSError(domain: "ImageIOThumbnailer", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "이미지 소스를 만들지 못했습니다."
            ])
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: policy.maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw NSError(domain: "ImageIOThumbnailer", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "썸네일 생성에 실패했습니다."
            ])
        }

        let thumbData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            thumbData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "ImageIOThumbnailer", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "이미지 목적지를 만들지 못했습니다."
            ])
        }

        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: policy.quality
        ]

        CGImageDestinationAddImage(dest, cgThumb, props as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "ImageIOThumbnailer", code: -4, userInfo: [
                NSLocalizedDescriptionKey: "JPEG 인코딩에 실패했습니다."
            ])
        }

        return thumbData as Data
    }
}
