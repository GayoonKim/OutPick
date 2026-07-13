import Foundation

struct KakaoFirebaseAuthBridgeResponse {
    let firebaseCustomToken: String
    let identityKey: String
    let providerUserID: String
    let email: String?
}

protocol KakaoAuthBridgeCalling {
    func exchangeKakaoToken(
        accessToken: String
    ) async throws -> KakaoFirebaseAuthBridgeResponse
}
