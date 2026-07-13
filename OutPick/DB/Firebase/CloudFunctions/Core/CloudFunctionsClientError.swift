import Foundation

enum CloudFunctionsClientError: LocalizedError, Equatable {
    case invalidResponse
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Cloud Functions 응답 형식이 올바르지 않습니다."
        case .missingField(let field):
            return "Cloud Functions 응답에 \(field) 값이 없습니다."
        }
    }
}
