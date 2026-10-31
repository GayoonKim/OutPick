import Foundation
import FirebaseFunctions

final class FirebaseCloudFunctionsTransport: CloudFunctionsTransporting {
    private static let region = "asia-northeast3"

    private let functions: Functions
    private let preservingErrorDetailsForCalls: Set<String>

    init(functions: Functions = Functions.functions(region: FirebaseCloudFunctionsTransport.region),
         preservingErrorDetailsForCalls: Set<String> = []) {
        self.functions = functions
        self.preservingErrorDetailsForCalls = preservingErrorDetailsForCalls
    }

    func call(
        _ name: String,
        data: [String: Any]
    ) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            functions.httpsCallable(name).call(data) { result, error in
                if let error {
                    continuation.resume(throwing: Self.mapError(error,
                        preservingDetails: self.preservingErrorDetailsForCalls.contains(name)))
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

    static func mapError(_ error: Error, preservingDetails: Bool) -> Error {
        let nsError = error as NSError
        if !preservingDetails, nsError.domain == FunctionsErrorDomain,
           nsError.code == FunctionsErrorCode.resourceExhausted.rawValue {
            return CloudFunctionsTransportError.rateLimited
        }
        return error
    }
}
