import Foundation
import FirebaseFunctions

final class FirebaseCloudFunctionsTransport: CloudFunctionsTransporting {
    private static let region = "asia-northeast3"

    private let functions: Functions

    init(functions: Functions = Functions.functions(region: FirebaseCloudFunctionsTransport.region)) {
        self.functions = functions
    }

    func call(
        _ name: String,
        data: [String: Any]
    ) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            functions.httpsCallable(name).call(data) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                do {
                    continuation.resume(
                        returning: try CloudFunctionResponseDecoder.dictionary(
                            from: result?.data
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
