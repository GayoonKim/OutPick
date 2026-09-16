//
//  LookbookSmokeUITests.swift
//  OutPickUITests
//
//  Created by Codex on 5/14/26.
//

import XCTest

final class LookbookSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPostDetailOpens() throws {
        try LookbookUITestSupport.requireFailureUITestOptIn()
        let app = LookbookUITestSupport.launchApp()

        try LookbookUITestSupport.openFirstPostDetail(in: app)

        XCTAssertTrue(
            LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.post.likeButton").exists,
            "포스트 상세 화면의 좋아요 버튼을 찾지 못했습니다."
        )
    }

    func testLikeFailureToastSmoke() throws {
        try LookbookUITestSupport.requireFailureUITestOptIn()
        let app = LookbookUITestSupport.launchApp(failureArgument: "--lookbook-fail-toggle-like")
        try LookbookUITestSupport.openFirstPostDetail(in: app)

        LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.post.likeButton").tap()

        LookbookUITestSupport.assertToast("좋아요를 반영하지 못했어요.", in: app)
    }

    func testCommentCreationFailureToastSmoke() throws {
        try LookbookUITestSupport.requireFailureUITestOptIn()
        let app = LookbookUITestSupport.launchApp(failureArgument: "--lookbook-fail-create-comment")
        try LookbookUITestSupport.openCommentsSheet(in: app)

        let input = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.comment.input")
        input.tap()
        input.typeText("실패 UX 댓글 smoke 테스트")
        LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.comment.submitButton").tap()

        LookbookUITestSupport.assertToast("댓글을 등록하지 못했어요.", in: app)
    }

    func testImageRetryDoesNotOpenCardDetail() throws {
        let app = LookbookUITestSupport.launchApp(failureArgument: "--uitest-lookbook-image-fail-once")
        let retry = app.buttons["이미지 다시 시도"].firstMatch

        XCTAssertTrue(retry.waitForExistence(timeout: 10), "브랜드 이미지 재시도가 표시되지 않았습니다.")
        retry.tap()
        XCTAssertFalse(LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.season.card").exists)
        assertRetryCompletes(retry)

        let brandCard = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.brand.card")
        brandCard.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 10), "시즌 이미지 재시도가 표시되지 않았습니다.")
        retry.tap()
        XCTAssertFalse(LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.post.card").exists)
        assertRetryCompletes(retry)

        let seasonCard = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.season.card")
        seasonCard.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 10), "포스트 이미지 재시도가 표시되지 않았습니다.")
        retry.tap()
        XCTAssertFalse(LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.post.likeButton").exists)
        assertRetryCompletes(retry)
    }

    private func assertRetryCompletes(_ retry: XCUIElement) {
        let disappeared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: retry
        )
        XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 5), .completed)
    }
}
