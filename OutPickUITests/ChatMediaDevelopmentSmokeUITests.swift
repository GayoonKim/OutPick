import XCTest

/// 실제 저장 세션·Development 서버를 이용한다. 로그인/메인 화면 fixture를 주입하지 않는다.
final class ChatMediaDevelopmentSmokeUITests: XCTestCase {
    func testRealDevelopmentAppReachesMainScreen() throws {
        guard ProcessInfo.processInfo.environment["OUTPICK_REAL_APP_SMOKE"] == "1" else {
            throw XCTSkip("실기기 실제 Development 세션 QA 명시 실행 전용")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-FIRDebugEnabled"]
        app.launch()
        let ready = app.otherElements["app.main.root"].waitForExistence(timeout: 90)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = ready ? "실제 Development 메인 화면" : "Development 진입 실패 화면"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(ready, "실제 Development 인증·bootstrap 후 메인 화면이어야 합니다.")
        XCTAssertFalse(app.staticTexts["app.bootstrap.failure.title"].exists)
        XCTAssertEqual(app.state, .runningForeground)
    }
}
