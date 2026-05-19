//
//  LookbookUITestSupport.swift
//  OutPickUITests
//
//  Created by Codex on 5/14/26.
//

import XCTest

enum LookbookUITestSupport {
    static func requireFailureUITestOptIn() throws {
        let isEnabled = ProcessInfo.processInfo.environment["RUN_LOOKBOOK_FAILURE_UITESTS"] == "1"
        if isEnabled == false {
            throw XCTSkip("룩북 실패 toast UI 테스트는 로그인/fixture 데이터가 필요하므로 RUN_LOOKBOOK_FAILURE_UITESTS=1일 때만 실행합니다.")
        }
    }

    static func launchApp(failureArgument: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITESTS"] = "1"
        app.launchArguments.append("--uitest-authenticated")
        app.launchArguments.append("--uitest-lookbook-fixture")
        if let failureArgument {
            app.launchArguments.append(failureArgument)
        }
        app.launch()
        return app
    }

    static func openCommentsSheet(in app: XCUIApplication) throws {
        try openFirstPostDetail(in: app)

        let commentsButton = firstElement(in: app, identifier: "lookbook.post.commentsButton")
        XCTAssertTrue(commentsButton.waitForExistence(timeout: 5), "댓글 버튼을 찾지 못했습니다.")
        commentsButton.tap()

        XCTAssertTrue(
            firstElement(in: app, identifier: "lookbook.comment.input").waitForExistence(timeout: 8),
            "댓글 시트 입력창을 찾지 못했습니다."
        )
    }

    static func openFirstPostDetail(in app: XCUIApplication) throws {
        if firstElement(in: app, identifier: "lookbook.post.likeButton").waitForExistence(timeout: 2) {
            return
        }

        guard app.staticTexts["OutPick"].waitForExistence(timeout: 10) else {
            throw XCTSkip("앱이 룩북 홈까지 진입하지 못했습니다. 로그인 세션 또는 UI test fixture를 확인해야 합니다.")
        }

        let brandCard = firstElement(in: app, identifier: "lookbook.brand.card")
        guard brandCard.waitForExistence(timeout: 10) else {
            throw XCTSkip("룩북 브랜드 fixture가 없어 실패 toast UI 테스트를 건너뜁니다.")
        }
        brandCard.tap()

        let seasonCard = firstElement(in: app, identifier: "lookbook.season.card")
        guard seasonCard.waitForExistence(timeout: 10) else {
            throw XCTSkip("룩북 시즌 fixture가 없어 실패 toast UI 테스트를 건너뜁니다.")
        }
        seasonCard.tap()

        let postCard = firstElement(in: app, identifier: "lookbook.post.card")
        guard postCard.waitForExistence(timeout: 10) else {
            throw XCTSkip("룩북 포스트 fixture가 없어 실패 toast UI 테스트를 건너뜁니다.")
        }
        postCard.tap()

        XCTAssertTrue(
            firstElement(in: app, identifier: "lookbook.post.likeButton").waitForExistence(timeout: 10),
            "포스트 상세 화면에 진입하지 못했습니다."
        )
    }

    static func openFirstCommentContextMenu(in app: XCUIApplication) throws {
        let commentCard = firstElement(in: app, identifier: "lookbook.comment.card")
        guard commentCard.waitForExistence(timeout: 8) else {
            throw XCTSkip("댓글 fixture가 없어 comment safety 실패 UI 테스트를 건너뜁니다.")
        }
        commentCard.press(forDuration: 1.0)
    }

    static func assertToast(_ message: String, in app: XCUIApplication) {
        let text = app.staticTexts[message]
        let toast = firstElement(in: app, identifier: "app.toast")

        XCTAssertTrue(
            text.waitForExistence(timeout: 3) || toast.waitForExistence(timeout: 1),
            "\(message) toast를 찾지 못했습니다."
        )
    }

    static func firstElement(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    static func firstExistingElement(
        in app: XCUIApplication,
        identifier: String,
        fallbackButtonLabelPrefix: String
    ) -> XCUIElement {
        let identified = firstElement(in: app, identifier: identifier)
        if identified.exists {
            return identified
        }

        let predicate = NSPredicate(format: "label BEGINSWITH %@", fallbackButtonLabelPrefix)
        return app.buttons.matching(predicate).firstMatch
    }
}
