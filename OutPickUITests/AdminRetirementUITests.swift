import XCTest

final class AdminRetirementUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPublicBrowsingHasNoAdminEntry() {
        let app = LookbookUITestSupport.launchApp()
        let brand = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.brand.card")
        XCTAssertTrue(brand.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Lookbook 관리자"].exists)
        brand.tap()
        XCTAssertTrue(LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.season.card").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["브랜드 관리자"].exists)
        XCTAssertFalse(app.buttons["시즌 추가"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "공개 브랜드 상세 관리자 진입 제거"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testOtherAuthorsCommentHasReportAndBlockWithoutDelete() throws {
        let app = LookbookUITestSupport.launchApp()
        try LookbookUITestSupport.openCommentsSheet(in: app)
        let comment = app.staticTexts["UI 테스트용 루트 댓글"].firstMatch
        XCTAssertTrue(comment.waitForExistence(timeout: 10))
        comment.press(forDuration: 1)
        XCTAssertTrue(app.buttons["신고"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["차단"].exists)
        XCTAssertFalse(app.buttons["삭제"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "타인 댓글 신고 차단 유지 삭제 없음"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testOwnCommentStillDeletes() throws {
        let app = LookbookUITestSupport.launchApp()
        try LookbookUITestSupport.openCommentsSheet(in: app)
        LookbookCommentsRobot(app: app)
            .deleteComment(message: "UI 테스트 사용자가 작성한 댓글")
            .assertCommentMessageDoesNotExist("UI 테스트 사용자가 작성한 댓글")
    }

    func testOwnReplyStillDeletes() throws {
        let app = LookbookUITestSupport.launchApp()
        try LookbookUITestSupport.openCommentsSheet(in: app)
        LookbookCommentsRobot(app: app)
            .openRepliesSheet()
            .deleteReply(message: "UI 테스트용 답글")
            .assertReplyMessageDoesNotExist("UI 테스트용 답글")
    }
}
