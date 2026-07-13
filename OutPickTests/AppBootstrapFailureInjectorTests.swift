import Testing
@testable import OutPick

struct AppBootstrapFailureInjectorTests {
    @Test func noFailureArgumentDoesNotInjectFailure() throws {
        let injector = AppBootstrapFailureInjector(arguments: ["OutPick"])

        try injector.throwIfNeeded()
        try injector.throwIfNeeded()
    }

    @Test func onceArgumentInjectsOnlyTheFirstAttempt() throws {
        let injector = AppBootstrapFailureInjector(
            arguments: ["OutPick", AppBootstrapFailureInjector.failDatabaseOnceArgument]
        )

        do {
            try injector.throwIfNeeded()
            Issue.record("첫 번째 시도에서 데이터베이스 초기화 실패가 주입되어야 합니다.")
        } catch let error as AppBootstrapFailureInjectionError {
            #expect(error == .databaseInitialization)
        }

        try injector.throwIfNeeded()
    }

    @Test func alwaysArgumentInjectsEveryAttempt() {
        let injector = AppBootstrapFailureInjector(
            arguments: ["OutPick", AppBootstrapFailureInjector.failDatabaseAlwaysArgument]
        )

        for _ in 0..<2 {
            do {
                try injector.throwIfNeeded()
                Issue.record("모든 시도에서 데이터베이스 초기화 실패가 주입되어야 합니다.")
            } catch let error as AppBootstrapFailureInjectionError {
                #expect(error == .databaseInitialization)
            } catch {
                Issue.record("예상하지 못한 오류입니다: \(error)")
            }
        }
    }

    @Test func alwaysArgumentTakesPriorityWhenBothArgumentsExist() {
        let injector = AppBootstrapFailureInjector(
            arguments: [
                "OutPick",
                AppBootstrapFailureInjector.failDatabaseOnceArgument,
                AppBootstrapFailureInjector.failDatabaseAlwaysArgument
            ]
        )

        for _ in 0..<2 {
            #expect(throws: AppBootstrapFailureInjectionError.databaseInitialization) {
                try injector.throwIfNeeded()
            }
        }
    }
}
