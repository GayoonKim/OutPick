//
//  LookbookPostDetailRobot.swift
//  OutPickUITests
//
//  Created by Codex on 5/21/26.
//

import XCTest

struct LookbookPostDetailRobot {
    private let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    @discardableResult
    func assertLikeCount(_ count: Int, timeout: TimeInterval = 10) -> Self {
        assertMetricButton(
            identifier: "lookbook.post.likeButton",
            expectedCount: count,
            missingMessage: "Test Firebase 좋아요 버튼을 찾지 못했습니다.",
            mismatchMessage: "좋아요 수가 기대 값과 다릅니다.",
            timeout: timeout
        )
        return self
    }

    @discardableResult
    func assertSaveCount(_ count: Int, timeout: TimeInterval = 10) -> Self {
        assertMetricButton(
            identifier: "lookbook.post.saveButton",
            expectedCount: count,
            missingMessage: "Test Firebase 저장 버튼을 찾지 못했습니다.",
            mismatchMessage: "저장 수가 기대 값과 다릅니다.",
            timeout: timeout
        )
        return self
    }

    @discardableResult
    func tapLike() -> Self {
        tapMetricButton(identifier: "lookbook.post.likeButton", missingMessage: "Test Firebase 좋아요 버튼을 찾지 못했습니다.")
        return self
    }

    @discardableResult
    func tapSave() -> Self {
        tapMetricButton(identifier: "lookbook.post.saveButton", missingMessage: "Test Firebase 저장 버튼을 찾지 못했습니다.")
        return self
    }

    private func assertMetricButton(
        identifier: String,
        expectedCount: Int,
        missingMessage: String,
        mismatchMessage: String,
        timeout: TimeInterval
    ) {
        let button = LookbookUITestSupport.firstElement(in: app, identifier: identifier)
        XCTAssertTrue(button.waitForExistence(timeout: timeout), missingMessage)
        let predicate = NSPredicate(format: "label CONTAINS %@", "\(expectedCount)")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: button)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(mismatchMessage) expected=\(expectedCount), label=\(button.label)")
    }

    private func tapMetricButton(identifier: String, missingMessage: String) {
        let button = LookbookUITestSupport.firstElement(in: app, identifier: identifier)
        XCTAssertTrue(button.waitForExistence(timeout: 10), missingMessage)
        button.tap()
    }
}
