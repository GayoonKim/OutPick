//
//  LookbookCommentsRobot.swift
//  OutPickUITests
//
//  Created by Codex on 5/21/26.
//

import XCTest

struct LookbookCommentsRobot {
    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    @discardableResult
    func openRepliesSheet(replyCount: Int = 1) -> Self {
        let repliesButton = app.buttons["답글 \(replyCount)개 보기 및 작성"]
        let commentsScrollView = app.scrollViews.firstMatch
        for _ in 0..<4 where repliesButton.exists == false {
            commentsScrollView.swipeUp()
        }

        XCTAssertTrue(repliesButton.waitForExistence(timeout: 10), "답글 버튼을 찾지 못했습니다.")
        repliesButton.tap()

        let input = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.comment.input")
        XCTAssertTrue(input.waitForExistence(timeout: 8), "답글 입력창을 찾지 못했습니다.")
        return self
    }

    @discardableResult
    func submitComment(_ message: String) -> Self {
        submitMessage(message, missingInputMessage: "댓글 입력창을 찾지 못했습니다.", missingSubmitMessage: "댓글 등록 버튼을 찾지 못했습니다.")
        return self
    }

    @discardableResult
    func submitReply(_ message: String) -> Self {
        submitMessage(message, missingInputMessage: "답글 입력창을 찾지 못했습니다.", missingSubmitMessage: "답글 등록 버튼을 찾지 못했습니다.")
        return self
    }

    @discardableResult
    func assertCommentMessageExists(_ message: String, timeout: TimeInterval = 10) -> Self {
        assertMessageExists(message, timeout: timeout, missingMessage: "작성한 댓글을 화면에서 찾지 못했습니다.")
        return self
    }

    @discardableResult
    func assertReplyMessageExists(_ message: String, timeout: TimeInterval = 10) -> Self {
        assertMessageExists(message, timeout: timeout, missingMessage: "작성한 답글을 화면에서 찾지 못했습니다.")
        return self
    }

    @discardableResult
    func deleteComment(message: String) -> Self {
        deleteMessage(
            message,
            missingMessage: "삭제할 댓글을 화면에서 찾지 못했습니다.",
            missingDeleteActionMessage: "댓글 삭제 메뉴를 찾지 못했습니다.",
            missingConfirmMessage: "댓글 삭제 확인 버튼을 찾지 못했습니다."
        )
        return self
    }

    @discardableResult
    func deleteReply(message: String) -> Self {
        deleteMessage(
            message,
            missingMessage: "삭제할 답글을 화면에서 찾지 못했습니다.",
            missingDeleteActionMessage: "답글 삭제 메뉴를 찾지 못했습니다.",
            missingConfirmMessage: "답글 삭제 확인 버튼을 찾지 못했습니다."
        )
        return self
    }

    @discardableResult
    func assertCommentMessageDoesNotExist(_ message: String, timeout: TimeInterval = 10) -> Self {
        assertMessageDoesNotExist(message, timeout: timeout, failureMessage: "삭제한 댓글이 화면에 남아 있습니다.")
        return self
    }

    @discardableResult
    func assertReplyMessageDoesNotExist(_ message: String, timeout: TimeInterval = 10) -> Self {
        assertMessageDoesNotExist(message, timeout: timeout, failureMessage: "삭제한 답글이 화면에 남아 있습니다.")
        return self
    }

    private func submitMessage(
        _ message: String,
        missingInputMessage: String,
        missingSubmitMessage: String
    ) {
        let input = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.comment.input")
        XCTAssertTrue(input.waitForExistence(timeout: 8), missingInputMessage)
        input.tap()
        input.typeText(message)

        let submitButton = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.comment.submitButton")
        XCTAssertTrue(submitButton.waitForExistence(timeout: 5), missingSubmitMessage)
        submitButton.tap()
    }

    private func assertMessageExists(_ message: String, timeout: TimeInterval, missingMessage: String) {
        let commentText = app.staticTexts[message]
        XCTAssertTrue(commentText.waitForExistence(timeout: timeout), "\(missingMessage) message=\(message)")
    }

    private func deleteMessage(
        _ message: String,
        missingMessage: String,
        missingDeleteActionMessage: String,
        missingConfirmMessage: String
    ) {
        let messageText = app.staticTexts[message]
        XCTAssertTrue(messageText.waitForExistence(timeout: 10), "\(missingMessage) message=\(message)")
        messageText.press(forDuration: 1.0)

        let deleteAction = firstAvailableElement(
            identifier: "lookbook.comment.deleteAction",
            fallbackButtonLabel: "삭제"
        )
        XCTAssertTrue(deleteAction.waitForExistence(timeout: 8), missingDeleteActionMessage)
        deleteAction.tap()

        let confirmButton = firstAvailableElement(
            identifier: "lookbook.comment.deleteConfirmButton",
            fallbackButtonLabel: "삭제하기"
        )
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 8), missingConfirmMessage)
        confirmButton.tap()
    }

    private func assertMessageDoesNotExist(_ message: String, timeout: TimeInterval, failureMessage: String) {
        let messageText = app.staticTexts[message]
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: messageText)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(failureMessage) message=\(message)")
    }

    private func firstAvailableElement(identifier: String, fallbackButtonLabel: String) -> XCUIElement {
        let identifiedElement = LookbookUITestSupport.firstElement(in: app, identifier: identifier)
        if identifiedElement.exists {
            return identifiedElement
        }
        return app.buttons[fallbackButtonLabel]
    }
}
