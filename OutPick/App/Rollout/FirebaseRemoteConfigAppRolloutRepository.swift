import FirebaseRemoteConfig
import Foundation
import OSLog

@MainActor
final class FirebaseRemoteConfigAppRolloutRepository: AppRolloutConfigurationRepositoryProtocol {
    private enum Key {
        static let minimumSupportedIOSVersion = "minimum_supported_ios_version"
        static let moderatorDelegationEnabled = "chat_room_moderator_delegation_enabled"
        static let appStoreURL = "ios_app_store_url"
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OutPick",
        category: "AppRollout"
    )

    private let remoteConfig: RemoteConfig

    init(remoteConfig: RemoteConfig = .remoteConfig()) {
        self.remoteConfig = remoteConfig
        let settings = RemoteConfigSettings()
        #if DEBUG
        settings.minimumFetchInterval = 0
        #else
        settings.minimumFetchInterval = 3_600
        #endif
        remoteConfig.configSettings = settings
        remoteConfig.setDefaults([
            Key.minimumSupportedIOSVersion: "0.0.0" as NSObject,
            Key.moderatorDelegationEnabled: false as NSObject,
            Key.appStoreURL: "" as NSObject
        ])
    }

    func loadConfiguration() async -> AppRolloutConfiguration {
        await fetchAndActivate()
        let appStoreURL = remoteConfig[Key.appStoreURL].stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AppRolloutConfiguration(
            minimumSupportedIOSVersion:
                remoteConfig[Key.minimumSupportedIOSVersion].stringValue,
            isChatRoomModeratorDelegationEnabled:
                remoteConfig[Key.moderatorDelegationEnabled].boolValue,
            appStoreURL: appStoreURL.isEmpty ? nil : appStoreURL
        )
    }

    private func fetchAndActivate() async {
        await withCheckedContinuation { continuation in
            remoteConfig.fetchAndActivate { _, error in
                if let error {
                    Self.logger.error(
                        "Remote Config 갱신 실패. 활성 캐시 또는 기본값을 사용합니다: \(String(describing: error), privacy: .private)"
                    )
                }
                continuation.resume()
            }
        }
    }
}
