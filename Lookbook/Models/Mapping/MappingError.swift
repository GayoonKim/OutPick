//
//  MappingError.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

enum MappingError: Error, LocalizedError {
    case missingDocumentID
    case invalidURL(String)
    case invalidEnumValue(String)
    case missingRequiredField(String)

    var errorDescription: String? {
        switch self {
        case .missingDocumentID: return "문서 ID(@DocumentID)가 없습니다."
        case .invalidURL(let v): return "URL 파싱 실패: \(v)"
        case .invalidEnumValue(let v): return "열거형 값이 유효하지 않음: \(v)"
        case .missingRequiredField(let v): return "필드 \(v)가 필요합니다."
        }
    }
}
