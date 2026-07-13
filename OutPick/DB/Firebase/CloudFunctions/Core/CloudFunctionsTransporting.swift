import Foundation

protocol CloudFunctionsTransporting {
    func call(
        _ name: String,
        data: [String: Any]
    ) async throws -> [String: Any]
}
