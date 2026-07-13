import Foundation

final class CloudFunctionsKakaoAuthBridgeClient: KakaoAuthBridgeCalling {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting) {
        self.transport = transport
    }

    func exchangeKakaoToken(
        accessToken: String
    ) async throws -> KakaoFirebaseAuthBridgeResponse {
        let response = try await transport.call(
            "exchangeKakaoToken",
            data: ["accessToken": accessToken]
        )
        let decoder = CloudFunctionResponseDecoder(dictionary: response)

        return KakaoFirebaseAuthBridgeResponse(
            firebaseCustomToken: try decoder.string("firebaseCustomToken"),
            identityKey: try decoder.string("identityKey"),
            providerUserID: try decoder.string("providerUserID"),
            email: decoder.optionalString("email")
        )
    }
}
