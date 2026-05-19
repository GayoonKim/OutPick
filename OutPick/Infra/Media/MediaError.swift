//
//  MediaError.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation

/// 미디어(이미지/비디오) 가공 단계에서 발생하는 오류
enum MediaError: LocalizedError {
    case failedToConvertImage
    case failedToCreateImageData
    case unsupportedType

    var errorDescription: String? {
        switch self {
        case .failedToConvertImage:
            return "이미지 변환에 실패했습니다."
        case .failedToCreateImageData:
            return "이미지 데이터 생성에 실패했습니다."
        case .unsupportedType:
            return "지원되지 않는 미디어 타입입니다."
        }
    }
}
