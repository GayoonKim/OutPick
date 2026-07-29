import FirebaseAppCheck
import FirebaseCore

enum OutPickAppCheckProviderMode: Equatable {
    case debug
    case appAttest
}

enum OutPickAppCheckProviderPolicy {
    static func mode(isSimulator: Bool) -> OutPickAppCheckProviderMode {
        isSimulator ? .debug : .appAttest
    }

    static var currentMode: OutPickAppCheckProviderMode {
        #if targetEnvironment(simulator)
        return mode(isSimulator: true)
        #else
        return mode(isSimulator: false)
        #endif
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
