import XCTest

final class AppBootstrapFailureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnceFailureRecoversToMainScreenAfterRetry() {
        let app = launchApp(failureArgument: "--app-bootstrap-fail-database-once")
        let failureTitle = app.staticTexts["app.bootstrap.failure.title"]
        let retryButton = app.buttons["app.bootstrap.failure.retry"]

        XCTAssertTrue(failureTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(retryButton.exists)

        retryButton.tap()

        XCTAssertTrue(
            app.otherElements["app.main.root"].waitForExistence(timeout: 10),
            "재시도 후 메인 화면으로 진입해야 합니다."
        )
        XCTAssertFalse(failureTitle.exists)
    }

    func testAlwaysFailureRemainsRecoverableAfterRepeatedRetry() {
        let app = launchApp(failureArgument: "--app-bootstrap-fail-database-always")

        for _ in 0..<2 {
            let retryButton = app.buttons["app.bootstrap.failure.retry"]
            XCTAssertTrue(retryButton.waitForExistence(timeout: 5))
            retryButton.tap()
        }

        XCTAssertTrue(
            app.staticTexts["app.bootstrap.failure.title"].waitForExistence(timeout: 5),
            "반복 실패 시에도 종료되지 않고 실패 화면을 다시 표시해야 합니다."
        )
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func launchApp(failureArgument: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITESTS"] = "1"
        app.launchArguments += [
            "--uitest-authenticated",
            "--uitest-lookbook-fixture",
            failureArgument
        ]
        app.launch()
        return app
    }
}
