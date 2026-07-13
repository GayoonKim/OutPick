import Foundation

enum AppBootstrapError: LocalizedError {
    case localDatabaseInitializationFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .localDatabaseInitializationFailed:
            return "앱 데이터를 준비하지 못했습니다."
        }
    }
}
