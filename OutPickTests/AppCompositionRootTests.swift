import Testing
import UIKit
@testable import OutPick

@MainActor
struct AppCompositionRootTests {
    private enum StubDatabaseError: Error {
        case initializationFailed
    }

    @Test func databaseFailureIsMappedBeforeCoordinatorConstruction() {
        let window = UIWindow(frame: .zero)

        do {
            _ = try AppCompositionRoot.makeCoordinator(window: window) {
                throw StubDatabaseError.initializationFailed
            }
            Issue.record("데이터베이스 생성 실패가 bootstrap 오류로 전달되어야 합니다.")
        } catch AppBootstrapError.localDatabaseInitializationFailed(let underlying) {
            #expect(underlying is StubDatabaseError)
        } catch {
            Issue.record("예상하지 못한 오류입니다: \(error)")
        }
    }
}
