import Foundation
import Testing
@testable import OutPick

struct AppRuntimeConfigurationTests {
    private let productionSocketURL = "https://production.example.com"
    private let developmentKakaoNativeAppKey = "f5f18b00bc7b163aa5be39fef99e646d"
    private let productionKakaoNativeAppKey = "a2b20f7bedfb9582147f572ef004d0f0"

    @Test func developmentConfigurationAcceptsOnlyDevelopmentBoundaries() throws {
        let configuration = try makeConfiguration(
            environment: "development",
            bundleIdentifier: "GayoonKim.OutPick.dev",
            projectID: "outpick-test",
            socketURL: "https://development.example.com"
        )

        #expect(configuration.environment == .development)
        #expect(configuration.socketURL.absoluteString == "https://development.example.com")
    }

    @Test func productionConfigurationRequiresCanonicalSocket() throws {
        let configuration = try makeConfiguration(
            environment: "production",
            bundleIdentifier: "GayoonKim.OutPick",
            projectID: "outpick-664ae",
            socketURL: productionSocketURL
        )

        #expect(configuration.environment == .production)
        #expect(configuration.socketURL == configuration.productionSocketURL)
    }

    @Test func developmentRejectsProductionSocket() {
        expectError(.developmentUsesProductionSocket) {
            _ = try makeConfiguration(
                environment: "development",
                bundleIdentifier: "GayoonKim.OutPick.dev",
                projectID: "outpick-test",
                socketURL: productionSocketURL
            )
        }
    }

    @Test func firebaseBundleAndProjectMustMatchRuntimeEnvironment() throws {
        let configuration = try makeConfiguration(
            environment: "development",
            bundleIdentifier: "GayoonKim.OutPick.dev",
            projectID: "outpick-test",
            socketURL: "https://development.example.com"
        )
        let wrongBundle = try FirebaseClientConfiguration(dictionary: [
            "BUNDLE_ID": "GayoonKim.OutPick",
            "PROJECT_ID": "outpick-test",
            "CLIENT_ID": "development.apps.googleusercontent.com",
            "REVERSED_CLIENT_ID": "com.googleusercontent.apps.development"
        ])

        expectError(.firebaseBundleIdentifierMismatch) {
            try configuration.validate(firebase: wrongBundle)
        }
    }

    @Test func googleCallbackMustMatchFirebasePlist() throws {
        let configuration = try makeConfiguration(
            environment: "production",
            bundleIdentifier: "GayoonKim.OutPick",
            projectID: "outpick-664ae",
            socketURL: productionSocketURL
        )
        let wrongCallback = try FirebaseClientConfiguration(dictionary: [
            "BUNDLE_ID": "GayoonKim.OutPick",
            "PROJECT_ID": "outpick-664ae",
            "CLIENT_ID": "production.apps.googleusercontent.com",
            "REVERSED_CLIENT_ID": "com.googleusercontent.apps.wrong"
        ])

        expectError(.googleCallbackMismatch) {
            try configuration.validate(firebase: wrongCallback)
        }
    }

    @Test func kakaoCallbackMustMatchNativeAppKey() {
        expectError(.kakaoCallbackMismatch) {
            _ = try makeConfiguration(
                environment: "development",
                bundleIdentifier: "GayoonKim.OutPick.dev",
                projectID: "outpick-test",
                socketURL: "https://development.example.com",
                kakaoURLScheme: "kakaowrong-key"
            )
        }
    }

    @Test func developmentRejectsProductionKakaoConfiguration() {
        expectError(.kakaoEnvironmentMismatch) {
            _ = try makeConfiguration(
                environment: "development",
                bundleIdentifier: "GayoonKim.OutPick.dev",
                projectID: "outpick-test",
                socketURL: "https://development.example.com",
                kakaoNativeAppKey: productionKakaoNativeAppKey
            )
        }
    }

    @Test func productionRejectsDevelopmentKakaoConfiguration() {
        expectError(.kakaoEnvironmentMismatch) {
            _ = try makeConfiguration(
                environment: "production",
                bundleIdentifier: "GayoonKim.OutPick",
                projectID: "outpick-664ae",
                socketURL: productionSocketURL,
                kakaoNativeAppKey: developmentKakaoNativeAppKey
            )
        }
    }

    private func makeConfiguration(
        environment: String,
        bundleIdentifier: String,
        projectID: String,
        socketURL: String,
        kakaoNativeAppKey: String? = nil,
        kakaoURLScheme: String? = nil
    ) throws -> AppRuntimeConfiguration {
        let resolvedKakaoNativeAppKey = kakaoNativeAppKey ?? expectedKakaoNativeAppKey(
            for: environment
        )
        return try AppRuntimeConfiguration(
            infoDictionary: [
                "OUTPICK_ENVIRONMENT": environment,
                "OUTPICK_EXPECTED_FIREBASE_PROJECT_ID": projectID,
                "OUTPICK_SOCKET_URL": socketURL,
                "OUTPICK_PRODUCTION_SOCKET_URL": productionSocketURL,
                "OUTPICK_GOOGLE_REVERSED_CLIENT_ID": "com.googleusercontent.apps.development",
                "OUTPICK_KAKAO_NATIVE_APP_KEY": resolvedKakaoNativeAppKey,
                "OUTPICK_KAKAO_URL_SCHEME": kakaoURLScheme ?? "kakao\(resolvedKakaoNativeAppKey)"
            ],
            bundleIdentifier: bundleIdentifier
        )
    }

    private func expectedKakaoNativeAppKey(for environment: String) -> String {
        environment == "production" ? productionKakaoNativeAppKey : developmentKakaoNativeAppKey
    }

    private func expectError(
        _ expectedError: AppEnvironmentError,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            Issue.record("예상한 환경 검증 오류가 발생하지 않았습니다.")
        } catch let error as AppEnvironmentError {
            #expect(error == expectedError)
        } catch {
            Issue.record("예상하지 못한 오류입니다: \(error)")
        }
    }
}
