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
        try LookbookUITestSupport.requireFailureUITestOptIn()
    }

    func testPostDetailOpens() throws {
        let app = LookbookUITestSupport.launchApp()

        try LookbookUITestSupport.openFirstPostDetail(in: app)

        XCTAssertTrue(
            LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.post.likeButton").exists,
            "포스트 상세 화면의 좋아요 버튼을 찾지 못했습니다."
        )
    }

    func testLikeFailureToastSmoke() throws {
        let app = LookbookUITestSupport.launchApp(failureArgument: "--lookbook-fail-toggle-like")
        try LookbookUITestSupport.openFirstPostDetail(in: app)

        LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.post.likeButton").tap()

        LookbookUITestSupport.assertToast("좋아요를 반영하지 못했어요.", in: app)
    }

    func testCommentCreationFailureToastSmoke() throws {
        let app = LookbookUITestSupport.launchApp(failureArgument: "--lookbook-fail-create-comment")
        try LookbookUITestSupport.openCommentsSheet(in: app)

        let input = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.comment.input")
        input.tap()
        input.typeText("실패 UX 댓글 smoke 테스트")
        LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.comment.submitButton").tap()

        LookbookUITestSupport.assertToast("댓글을 등록하지 못했어요.", in: app)
    }
}
