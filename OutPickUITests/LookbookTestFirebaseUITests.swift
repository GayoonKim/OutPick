//
//  LookbookTestFirebaseUITests.swift
//  OutPickUITests
//
//  Created by Codex on 5/20/26.
//

import XCTest

final class LookbookTestFirebaseUITests: XCTestCase {
    private var testAdminServer: LookbookTestAdminServerClient!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try LookbookUITestSupport.requireTestFirebaseUITestOptIn()

        testAdminServer = LookbookTestAdminServerClient()
        try testAdminServer.assertHealthy()
    }

    func testSeededLookbookCommentsOpenFromTestFirebase() throws {
        try testAdminServer.reset()
        try testAdminServer.seed(.comments)

        let app = LookbookUITestSupport.launchAppUsingTestFirebase(authenticated: true)
        try LookbookUITestSupport.openCommentsSheet(in: app)

        let commentCard = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.comment.card")
        XCTAssertTrue(commentCard.waitForExistence(timeout: 10), "Test Firebase 댓글 seed를 화면에서 찾지 못했습니다.")
    }

    func testSeededLookbookPostLikeTogglesFromTestFirebase() throws {
        try testAdminServer.reset()
        try testAdminServer.seed(.basic)

        let app = LookbookUITestSupport.launchAppUsingTestFirebase(authenticated: true)
        try LookbookUITestSupport.openFirstPostDetail(in: app)

        LookbookPostDetailRobot(app: app)
            .assertLikeCount(3)
            .tapLike()
            .assertLikeCount(4)
    }

    func testSeededLookbookPostSaveTogglesFromTestFirebase() throws {
        try testAdminServer.reset()
        try testAdminServer.seed(.basic)

        let app = LookbookUITestSupport.launchAppUsingTestFirebase(authenticated: true)
        try LookbookUITestSupport.openFirstPostDetail(in: app)

        LookbookPostDetailRobot(app: app)
            .assertSaveCount(1)
            .tapSave()
            .assertSaveCount(2)
    }

    func testSeededLookbookCommentSubmitFromTestFirebase() throws {
        try testAdminServer.reset()
        try testAdminServer.seed(.basic)

        let message = "Test Firebase 댓글 작성 mutation"
        let app = LookbookUITestSupport.launchAppUsingTestFirebase(authenticated: true)
        try LookbookUITestSupport.openCommentsSheet(in: app)

        LookbookCommentsRobot(app: app)
            .submitComment(message)
            .assertCommentMessageExists(message)
    }

    func testSeededLookbookRepliesOpenFromTestFirebase() throws {
        try testAdminServer.reset()
        try testAdminServer.seed(.comments)

        let app = LookbookUITestSupport.launchAppUsingTestFirebase(authenticated: true)
        try LookbookUITestSupport.openCommentsSheet(in: app)

        let repliesButton = app.buttons["답글 1개 보기 및 작성"]
        let commentsScrollView = app.scrollViews.firstMatch
        for _ in 0..<4 where repliesButton.exists == false {
            commentsScrollView.swipeUp()
        }
        XCTAssertTrue(repliesButton.waitForExistence(timeout: 10), "Test Firebase 답글 버튼을 찾지 못했습니다.")
        repliesButton.tap()

        let replyText = app.staticTexts["대표 댓글 답글 테스트 데이터"]
        XCTAssertTrue(replyText.waitForExistence(timeout: 10), "Test Firebase 답글 seed를 화면에서 찾지 못했습니다.")
    }

    func testSeededLookbookReplySubmitFromTestFirebase() throws {
        try testAdminServer.reset()
        try testAdminServer.seed(.comments)

        let message = "Test Firebase 답글 작성 mutation"
        let app = LookbookUITestSupport.launchAppUsingTestFirebase(authenticated: true)
        try LookbookUITestSupport.openCommentsSheet(in: app)

        LookbookCommentsRobot(app: app)
            .openRepliesSheet(replyCount: 1)
            .submitReply(message)
            .assertReplyMessageExists(message)
    }

    func testSeededLookbookCommentDeleteFromTestFirebase() throws {
        try testAdminServer.reset()
        try testAdminServer.seed(.basic)

        let message = "Test Firebase 댓글 삭제 mutation"
        let app = LookbookUITestSupport.launchAppUsingTestFirebase(authenticated: true)
        try LookbookUITestSupport.openCommentsSheet(in: app)

        LookbookCommentsRobot(app: app)
            .submitComment(message)
            .assertCommentMessageExists(message)
            .deleteComment(message: message)
            .assertCommentMessageDoesNotExist(message)
    }

    func testSeededLookbookReplyDeleteFromTestFirebase() throws {
        try testAdminServer.reset()
        try testAdminServer.seed(.comments)

        let message = "Test Firebase 답글 삭제 mutation"
        let app = LookbookUITestSupport.launchAppUsingTestFirebase(authenticated: true)
        try LookbookUITestSupport.openCommentsSheet(in: app)

        LookbookCommentsRobot(app: app)
            .openRepliesSheet(replyCount: 1)
            .submitReply(message)
            .assertReplyMessageExists(message)
            .deleteReply(message: message)
            .assertReplyMessageDoesNotExist(message)
    }
}
