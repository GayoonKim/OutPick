//
//  LookbookInteractionFailureToastUITests.swift
//  OutPickUITests
//
//  Created by Codex on 5/13/26.
//

import XCTest

final class LookbookInteractionFailureToastUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try LookbookUITestSupport.requireFailureUITestOptIn()
    }

    func testLikeFailureShowsToast() throws {
        let app = LookbookUITestSupport.launchApp(failureArgument: "--lookbook-fail-toggle-like")
        try LookbookUITestSupport.openFirstPostDetail(in: app)

        LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.post.likeButton").tap()

        LookbookUITestSupport.assertToast("좋아요를 반영하지 못했어요.", in: app)
    }

    func testSaveFailureShowsToast() throws {
        let app = LookbookUITestSupport.launchApp(failureArgument: "--lookbook-fail-toggle-save")
        try LookbookUITestSupport.openFirstPostDetail(in: app)

        LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.post.saveButton").tap()

        LookbookUITestSupport.assertToast("저장을 반영하지 못했어요.", in: app)
    }

    func testCommentCreationFailureShowsToast() throws {
        let app = LookbookUITestSupport.launchApp(failureArgument: "--lookbook-fail-create-comment")
        try LookbookUITestSupport.openCommentsSheet(in: app)

        let input = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.comment.input")
        input.tap()
        input.typeText("실패 UX 댓글 테스트")
        LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.comment.submitButton").tap()

        LookbookUITestSupport.assertToast("댓글을 등록하지 못했어요.", in: app)
    }

    func testCommentDeletionFailureShowsToast() throws {
        let app = LookbookUITestSupport.launchApp(failureArgument: "--lookbook-fail-delete-comment")
        try LookbookUITestSupport.openCommentsSheet(in: app)
        try LookbookUITestSupport.openFirstCommentContextMenu(in: app)

        let deleteAction = app.buttons["삭제"]
        guard deleteAction.waitForExistence(timeout: 3) else {
            throw XCTSkip("삭제 가능한 내 댓글 fixture가 없어 댓글 삭제 실패 UI 테스트를 건너뜁니다.")
        }
        deleteAction.tap()

        let confirmDeleteButton = LookbookUITestSupport.firstElement(
            in: app,
            identifier: "lookbook.comment.deleteConfirmButton"
        )
        XCTAssertTrue(confirmDeleteButton.waitForExistence(timeout: 5), "댓글 삭제 확인 버튼을 찾지 못했습니다.")
        confirmDeleteButton.tap()

        LookbookUITestSupport.assertToast("댓글을 삭제하지 못했어요.", in: app)
    }

    func testReplyCreationFailureShowsToast() throws {
        let app = LookbookUITestSupport.launchApp(failureArgument: "--lookbook-fail-create-reply")
        try LookbookUITestSupport.openCommentsSheet(in: app)

        let repliesButton = LookbookUITestSupport.firstExistingElement(
            in: app,
            identifier: "lookbook.comment.repliesButton",
            fallbackButtonLabelPrefix: "답글"
        )
        guard repliesButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("답글이 있는 댓글 fixture가 없어 답글 작성 실패 UI 테스트를 건너뜁니다.")
        }
        repliesButton.tap()

        let input = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.comment.input")
        XCTAssertTrue(input.waitForExistence(timeout: 5), "답글 입력창을 찾지 못했습니다.")
        input.tap()
        input.typeText("실패 UX 답글 테스트")
        LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.comment.submitButton").tap()

        LookbookUITestSupport.assertToast("답글을 등록하지 못했어요.", in: app)
    }

    func testReportFailureShowsToast() throws {
        let app = LookbookUITestSupport.launchApp(failureArgument: "--lookbook-fail-report-comment")
        try LookbookUITestSupport.openCommentsSheet(in: app)
        try LookbookUITestSupport.openFirstCommentContextMenu(in: app)

        let reportAction = app.buttons["신고"]
        guard reportAction.waitForExistence(timeout: 3) else {
            throw XCTSkip("신고 가능한 댓글 fixture가 없어 신고 실패 UI 테스트를 건너뜁니다.")
        }
        reportAction.tap()

        let submitButton = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.comment.reportSubmitButton")
        XCTAssertTrue(submitButton.waitForExistence(timeout: 5), "신고 제출 버튼을 찾지 못했습니다.")
        submitButton.tap()

        LookbookUITestSupport.assertToast("댓글을 신고하지 못했어요.", in: app)
    }

    func testBlockFailureShowsToast() throws {
        let app = LookbookUITestSupport.launchApp(failureArgument: "--lookbook-fail-block-user")
        try LookbookUITestSupport.openCommentsSheet(in: app)
        try LookbookUITestSupport.openFirstCommentContextMenu(in: app)

        let blockAction = app.buttons["차단"]
        guard blockAction.waitForExistence(timeout: 3) else {
            throw XCTSkip("차단 가능한 댓글 fixture가 없어 차단 실패 UI 테스트를 건너뜁니다.")
        }
        blockAction.tap()

        let confirmButton = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.comment.blockConfirmButton")
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5), "차단 확인 버튼을 찾지 못했습니다.")
        confirmButton.tap()

        LookbookUITestSupport.assertToast("사용자를 차단하지 못했어요.", in: app)
    }
}
