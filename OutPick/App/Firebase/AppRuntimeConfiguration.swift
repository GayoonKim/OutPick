import Foundation

enum OutPickEnvironment: String, Equatable, Sendable {
    case development
    case production

    var expectedKakaoNativeAppKey: String {
        switch self {
        case .development:
            "f5f18b00bc7b163aa5be39fef99e646d"
        case .production:
            "a2b20f7bedfb9582147f572ef004d0f0"
        }
    }
}

struct FirebaseClientConfiguration: Equatable, Sendable {
    let bundleIdentifier: String
    let projectID: String
    let clientID: String?
    let reversedClientID: String?

    init(dictionary: [String: Any]) throws {
        bundleIdentifier = try Self.requiredString("BUNDLE_ID", in: dictionary)
        projectID = try Self.requiredString("PROJECT_ID", in: dictionary)
        clientID = Self.optionalString("CLIENT_ID", in: dictionary)
        reversedClientID = Self.optionalString("REVERSED_CLIENT_ID", in: dictionary)
    }

    init(contentsOfFile path: String) throws {
        guard let dictionary = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            throw AppEnvironmentError.invalidFirebasePlist
        }
        try self.init(dictionary: dictionary)
    }

    private static func requiredString(_ key: String, in dictionary: [String: Any]) throws -> String {
        guard let value = optionalString(key, in: dictionary) else {
            throw AppEnvironmentError.missingFirebaseValue(key)
        }
        return value
    }

    private static func optionalString(_ key: String, in dictionary: [String: Any]) -> String? {
        guard let rawValue = dictionary[key] as? String else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct AppRuntimeConfiguration: Equatable, Sendable {
    let environment: OutPickEnvironment
    let bundleIdentifier: String
    let expectedFirebaseProjectID: String
    let socketURL: URL
    let productionSocketURL: URL
    let googleReversedClientID: String
    let kakaoNativeAppKey: String
    let kakaoURLScheme: String

    init(infoDictionary: [String: Any], bundleIdentifier: String) throws {
        guard let environment = OutPickEnvironment(
            rawValue: try Self.requiredString("OUTPICK_ENVIRONMENT", in: infoDictionary)
        ) else {
            throw AppEnvironmentError.unsupportedEnvironment
        }

        let expectedFirebaseProjectID = try Self.requiredString(
            "OUTPICK_EXPECTED_FIREBASE_PROJECT_ID",
            in: infoDictionary
        )
        let socketURL = try Self.httpURL("OUTPICK_SOCKET_URL", in: infoDictionary)
        let productionSocketURL = try Self.httpURL("OUTPICK_PRODUCTION_SOCKET_URL", in: infoDictionary)
        let googleReversedClientID = try Self.requiredString(
            "OUTPICK_GOOGLE_REVERSED_CLIENT_ID",
            in: infoDictionary
        )
        let kakaoNativeAppKey = try Self.requiredString(
            "OUTPICK_KAKAO_NATIVE_APP_KEY",
            in: infoDictionary
        )
        let kakaoURLScheme = try Self.requiredString(
            "OUTPICK_KAKAO_URL_SCHEME",
            in: infoDictionary
        )
        guard kakaoNativeAppKey == environment.expectedKakaoNativeAppKey else {
            throw AppEnvironmentError.kakaoEnvironmentMismatch
        }
        guard kakaoURLScheme == "kakao\(environment.expectedKakaoNativeAppKey)" else {
            throw AppEnvironmentError.kakaoCallbackMismatch
        }

        switch environment {
        case .development:
            guard bundleIdentifier == "GayoonKim.OutPick.dev" else {
                throw AppEnvironmentError.bundleIdentifierMismatch
            }
            guard expectedFirebaseProjectID == "outpick-test" else {
                throw AppEnvironmentError.firebaseProjectMismatch
            }
            guard socketURL != productionSocketURL else {
                throw AppEnvironmentError.developmentUsesProductionSocket
            }
        case .production:
            guard bundleIdentifier == "GayoonKim.OutPick" else {
                throw AppEnvironmentError.bundleIdentifierMismatch
            }
            guard expectedFirebaseProjectID == "outpick-664ae" else {
                throw AppEnvironmentError.firebaseProjectMismatch
            }
            guard socketURL == productionSocketURL else {
                throw AppEnvironmentError.productionSocketMismatch
            }
        }

        self.environment = environment
        self.bundleIdentifier = bundleIdentifier
        self.expectedFirebaseProjectID = expectedFirebaseProjectID
        self.socketURL = socketURL
        self.productionSocketURL = productionSocketURL
        self.googleReversedClientID = googleReversedClientID
        self.kakaoNativeAppKey = kakaoNativeAppKey
        self.kakaoURLScheme = kakaoURLScheme
    }

    static func load(bundle: Bundle = .main) throws -> AppRuntimeConfiguration {
        guard let infoDictionary = bundle.infoDictionary,
              let bundleIdentifier = bundle.bundleIdentifier else {
            throw AppEnvironmentError.missingBundleConfiguration
        }
        return try AppRuntimeConfiguration(
            infoDictionary: infoDictionary,
            bundleIdentifier: bundleIdentifier
        )
    }

    func validate(
        firebase: FirebaseClientConfiguration,
        allowsMissingGoogleOAuth: Bool = false
    ) throws {
        guard firebase.bundleIdentifier == bundleIdentifier else {
            throw AppEnvironmentError.firebaseBundleIdentifierMismatch
        }
        guard firebase.projectID == expectedFirebaseProjectID else {
            throw AppEnvironmentError.firebaseProjectMismatch
        }

        if allowsMissingGoogleOAuth, firebase.clientID == nil, firebase.reversedClientID == nil {
            return
        }

        guard firebase.clientID != nil else {
            throw AppEnvironmentError.missingFirebaseValue("CLIENT_ID")
        }
        guard firebase.reversedClientID == googleReversedClientID else {
            throw AppEnvironmentError.googleCallbackMismatch
        }
    }

    private static func requiredString(_ key: String, in dictionary: [String: Any]) throws -> String {
        guard let rawValue = dictionary[key] as? String else {
            throw AppEnvironmentError.missingInfoValue(key)
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw AppEnvironmentError.missingInfoValue(key)
        }
        return value
    }

    private static func httpURL(_ key: String, in dictionary: [String: Any]) throws -> URL {
        let value = try requiredString(key, in: dictionary)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw AppEnvironmentError.invalidURL(key)
        }
        return url
    }
}

enum AppEnvironmentError: LocalizedError, Equatable {
    case missingBundleConfiguration
    case missingInfoValue(String)
    case unsupportedEnvironment
    case invalidURL(String)
    case bundleIdentifierMismatch
    case firebaseBundleIdentifierMismatch
    case firebaseProjectMismatch
    case developmentUsesProductionSocket
    case productionSocketMismatch
    case missingFirebasePlist
    case invalidFirebasePlist
    case missingFirebaseValue(String)
    case googleCallbackMismatch
    case kakaoEnvironmentMismatch
    case kakaoCallbackMismatch

    var errorDescription: String? {
        switch self {
        case .missingBundleConfiguration:
            "앱 Bundle 환경 설정을 읽을 수 없습니다."
        case .missingInfoValue(let key):
            "Info.plist의 \(key) 값이 없습니다."
        case .unsupportedEnvironment:
            "지원하지 않는 OutPick 환경입니다."
        case .invalidURL(let key):
            "Info.plist의 \(key) URL이 올바르지 않습니다."
        case .bundleIdentifierMismatch:
            "앱 환경과 Bundle ID가 일치하지 않습니다."
        case .firebaseBundleIdentifierMismatch:
            "앱 Bundle ID와 Firebase plist의 BUNDLE_ID가 일치하지 않습니다."
        case .firebaseProjectMismatch:
            "앱 환경과 Firebase project가 일치하지 않습니다."
        case .developmentUsesProductionSocket:
            "Development 앱은 Production Socket을 사용할 수 없습니다."
        case .productionSocketMismatch:
            "Production Socket URL이 canonical URL과 일치하지 않습니다."
        case .missingFirebasePlist:
            "앱 번들에 GoogleService-Info.plist가 없습니다."
        case .invalidFirebasePlist:
            "GoogleService-Info.plist를 읽을 수 없습니다."
        case .missingFirebaseValue(let key):
            "Firebase plist의 \(key) 값이 없습니다."
        case .googleCallbackMismatch:
            "Google OAuth callback scheme이 Firebase plist와 일치하지 않습니다."
        case .kakaoEnvironmentMismatch:
            "Kakao Native App Key가 앱 환경과 일치하지 않습니다."
        case .kakaoCallbackMismatch:
            "Kakao callback scheme이 앱 환경의 Native App Key와 일치하지 않습니다."
        }
    }
}
