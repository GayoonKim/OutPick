import Foundation

enum AppBootstrapFailureInjectionError: LocalizedError, Equatable {
    case databaseInitialization

    var errorDescription: String? {
        switch self {
        case .databaseInitialization:
            return "로컬 데이터베이스 초기화 실패가 주입되었습니다."
        }
    }
}

final class AppBootstrapFailureInjector {
    enum Mode: Equatable {
        case none
        case once
        case always
    }

    static let failDatabaseOnceArgument = "--app-bootstrap-fail-database-once"
    static let failDatabaseAlwaysArgument = "--app-bootstrap-fail-database-always"

    private let mode: Mode
    private var didInjectOnce = false

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
#if DEBUG
        if arguments.contains(Self.failDatabaseAlwaysArgument) {
            mode = .always
        } else if arguments.contains(Self.failDatabaseOnceArgument) {
            mode = .once
        } else {
            mode = .none
        }
#else
        mode = .none
#endif
    }

    func throwIfNeeded() throws {
        switch mode {
        case .none:
            return
        case .once where didInjectOnce:
            return
        case .once:
            didInjectOnce = true
            throw AppBootstrapFailureInjectionError.databaseInitialization
        case .always:
            throw AppBootstrapFailureInjectionError.databaseInitialization
        }
    }
}
