import Foundation
@testable import OutPick

final class CloudFunctionsTransportSpy: CloudFunctionsTransporting {
    struct Call {
        let name: String
        let data: [String: Any]
    }

    private(set) var calls: [Call] = []
    var responses: [[String: Any]] = []
    var error: Error?

    func call(
        _ name: String,
        data: [String: Any]
    ) async throws -> [String: Any] {
        calls.append(Call(name: name, data: data))
        if let error {
            throw error
        }
        return responses.isEmpty ? [:] : responses.removeFirst()
    }
}
