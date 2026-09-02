import Foundation

struct AppSemanticVersion: Comparable, Equatable, Sendable {
    let components: [Int]

    init?(_ value: String) {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard (1...3).contains(parts.count) else { return nil }
        let parsed = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy(\.isNumber) else { return nil }
            return Int(part)
        }
        guard parsed.count == parts.count else { return nil }
        components = parsed
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

struct AppRolloutConfiguration: Equatable, Sendable {
    let minimumSupportedIOSVersion: String
    let isChatRoomModeratorDelegationEnabled: Bool
    let appStoreURL: String?
}

enum AppRolloutDecision: Equatable, Sendable {
    case available(isChatRoomModeratorDelegationEnabled: Bool)
    case updateRequired(appStoreURL: URL?)
}

@MainActor
protocol AppRolloutConfigurationRepositoryProtocol {
    func loadConfiguration() async -> AppRolloutConfiguration
}

struct LoadAppRolloutDecisionUseCase {
    private let repository: any AppRolloutConfigurationRepositoryProtocol
    private let currentVersion: () -> String

    init(
        repository: any AppRolloutConfigurationRepositoryProtocol,
        currentVersion: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        }
    ) {
        self.repository = repository
        self.currentVersion = currentVersion
    }

    @MainActor
    func execute() async -> AppRolloutDecision {
        let configuration = await repository.loadConfiguration()
        guard let installed = AppSemanticVersion(currentVersion()),
              let minimum = AppSemanticVersion(configuration.minimumSupportedIOSVersion) else {
            return .available(isChatRoomModeratorDelegationEnabled: false)
        }
        if installed < minimum {
            return .updateRequired(appStoreURL: Self.validAppStoreURL(configuration.appStoreURL))
        }
        return .available(
            isChatRoomModeratorDelegationEnabled:
                configuration.isChatRoomModeratorDelegationEnabled
        )
    }

    private static func validAppStoreURL(_ value: String?) -> URL? {
        guard let value,
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "apps.apple.com",
              url.user == nil,
              url.password == nil else {
            return nil
        }
        return url
    }
}

@MainActor
protocol AppFeatureGateChecking: AnyObject {
    var isChatRoomModeratorDelegationEnabled: Bool { get }
}

@MainActor
final class AppFeatureGateStore: AppFeatureGateChecking {
    private(set) var isChatRoomModeratorDelegationEnabled = false

    func replace(isChatRoomModeratorDelegationEnabled: Bool) {
        self.isChatRoomModeratorDelegationEnabled = isChatRoomModeratorDelegationEnabled
    }
}
