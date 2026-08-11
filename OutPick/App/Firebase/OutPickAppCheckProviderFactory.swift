import FirebaseAppCheck
import FirebaseCore

enum OutPickAppCheckProviderMode: Equatable {
    case debug
    case appAttest
}

enum OutPickAppCheckProviderPolicy {
    static func mode(
        isDebugBuild: Bool,
        isSimulator: Bool
    ) -> OutPickAppCheckProviderMode {
        if isDebugBuild || isSimulator {
            return .debug
        }
        return .appAttest
    }

    static var currentMode: OutPickAppCheckProviderMode {
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif

        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif

        return mode(
            isDebugBuild: isDebugBuild,
            isSimulator: isSimulator
        )
    }
}

final class OutPickAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        switch OutPickAppCheckProviderPolicy.currentMode {
        case .debug:
            return AppCheckDebugProvider(app: app)
        case .appAttest:
            return AppAttestProvider(app: app)
        }
    }
}
