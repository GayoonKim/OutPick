//
//  ImageThumbnailing.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import UIKit

protocol ImageThumbnailing {
    /// policy를 받아 썸네일 JPEG 데이터를 생성합니다.
    func makeThumbnailJPEGData(from originalJPEGData: Data, policy: ThumbnailPolicy) throws -> Data
}

extension ImageThumbnailing {
    /// 기본 정책(ThumbnailPolicy.default)으로 썸네일 JPEG 데이터를 생성합니다.
    func makeThumbnailJPEGData(from originalJPEGData: Data) throws -> Data {
        try makeThumbnailJPEGData(from: originalJPEGData, policy: .default)
    }
}
