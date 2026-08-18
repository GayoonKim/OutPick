import Foundation

enum CloudFunctionsTransportError: Error {
    case rateLimited
}

protocol CloudFunctionsTransporting {
    func call(
        _ name: String,
        data: [String: Any]
    ) async throws -> [String: Any]
}
