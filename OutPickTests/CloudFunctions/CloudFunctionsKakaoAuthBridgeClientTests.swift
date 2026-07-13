import Foundation
import Testing
@testable import OutPick

struct CloudFunctionsKakaoAuthBridgeClientTests {
    @Test func exchangesKakaoTokenWithExpectedPayload() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [[
            "firebaseCustomToken": "firebase-token",
            "identityKey": "kakao:123",
            "providerUserID": "123",
            "email": "user@example.com"
        ]]
        let client = CloudFunctionsKakaoAuthBridgeClient(transport: transport)

        let response = try await client.exchangeKakaoToken(accessToken: "access-token")

        #expect(transport.calls.count == 1)
        #expect(transport.calls[0].name == "exchangeKakaoToken")
        #expect(transport.calls[0].data["accessToken"] as? String == "access-token")
        #expect(response.firebaseCustomToken == "firebase-token")
        #expect(response.identityKey == "kakao:123")
        #expect(response.providerUserID == "123")
        #expect(response.email == "user@example.com")
    }

    @Test func preservesTransportError() async {
        let expected = NSError(domain: "com.firebase.functions", code: 16)
        let transport = CloudFunctionsTransportSpy()
        transport.error = expected
        let client = CloudFunctionsKakaoAuthBridgeClient(transport: transport)

        do {
            _ = try await client.exchangeKakaoToken(accessToken: "token")
            Issue.record("오류가 전달되어야 합니다.")
        } catch {
            let received = error as NSError
            #expect(received.domain == expected.domain)
            #expect(received.code == expected.code)
        }
    }
}
