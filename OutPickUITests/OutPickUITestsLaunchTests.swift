// OutPickUITests/OutPickUITestsLaunchTests.swift
import XCTest

final class OutPickUITestsLaunchTests: XCTestCase {

    // 각 기기/환경 설정별로 한 번씩 실행
    override class var runsForEachTargetApplicationUIConfiguration: Bool { true }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 앱이 정상적으로 실행되는지만 확인 (의존성 최소화)
    func testLaunch() throws {
        let app = XCUIApplication()
        // 테스트 전용 플래그(앱에서 필요하면 활용 가능)
        app.launchEnvironment["UITESTS"] = "1"
        app.launch()

        // 실행 상태 확인
        XCTAssertEqual(app.state, .runningForeground, "앱이 포그라운드로 실행되지 않았습니다.")
    }

    /// (선택) 런치 성능 측정 — iOS 15+ 에서만
    func testLaunchPerformance() throws {
        guard #available(iOS 15.0, *) else {
            throw XCTSkip("iOS 15 미만은 런치 성능 측정을 스킵합니다.")
        }
        // CI 환경에서 과도한 측정을 피하고 싶다면 아래 주석 해제
        // if ProcessInfo.processInfo.environment["CI"] == "1" { throw XCTSkip("CI에서는 스킵") }

        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchEnvironment["UITESTS"] = "1"
            app.launch()
        }
    }
}
