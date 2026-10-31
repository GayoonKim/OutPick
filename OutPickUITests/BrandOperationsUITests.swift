import XCTest

final class BrandOperationsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testRequestEntryWithResultsURLFormHistoryAndCompletedNavigation() {
        let app = LookbookUITestSupport.launchApp()
        let search = app.textFields["브랜드 검색"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("UI Test Brand")
        let entry = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.brandRequest.entry")
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        XCTAssertFalse(app.buttons["요청하기"].isEnabled)
        let url = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.brandRequest.websiteURL")
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.tap()
        url.typeText("https://brand.example\n")
        let submit = app.buttons["요청하기"]
        if !submit.isHittable { app.swipeUp() }
        XCTAssertTrue(submit.isEnabled)
        submit.tap()
        XCTAssertTrue(app.staticTexts["브랜드 요청 상황"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["등록 완료"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["내 요청 내역 보기"].exists)
        XCTAssertFalse(url.exists)
        XCTAssertTrue(app.staticTexts["공식 룩북 확인 필요"].waitForExistence(timeout: 5))
        app.buttons["브랜드 보기"].firstMatch.tap()
        XCTAssertTrue(LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.season.card").waitForExistence(timeout: 5))
    }

    func testRequestEntryWithoutResultsAndFourStatusHistory() {
        let app = LookbookUITestSupport.launchApp()
        let search = app.textFields["브랜드 검색"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("없는브랜드")
        let entry = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.brandRequest.entry")
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let url = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.brandRequest.websiteURL")
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.tap()
        url.typeText("https://newbrand.example\n")
        let submit = app.buttons["요청하기"]
        if !submit.isHittable { app.swipeUp() }
        submit.tap()
        XCTAssertTrue(app.staticTexts["브랜드 요청 상황"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["내 요청 내역 보기"].exists)
        XCTAssertFalse(url.exists)
        XCTAssertTrue(app.staticTexts["요청 접수"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["처리 중"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2026.05.18 7:26 PM"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "한국 시간")).firstMatch.exists)
        let dateScreenshot = XCTAttachment(screenshot: app.screenshot())
        dateScreenshot.name = "브랜드 요청 한국식 날짜와 시각"
        dateScreenshot.lifetime = .keepAlways
        add(dateScreenshot)
        app.buttons["이전 요청"].tap()
        XCTAssertTrue(app.staticTexts["등록 완료"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["보류"].exists)
        XCTAssertTrue(app.staticTexts["공식 룩북 확인 필요"].exists)
        app.buttons["뒤로 가기"].firstMatch.tap()
        XCTAssertTrue(app.textFields["브랜드 검색"].waitForExistence(timeout: 5))
        XCTAssertFalse(LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.brandRequest.websiteURL").exists)
    }

    func testSubmissionFailureShowsSingleFriendlyAlertAndKeepsInput() {
        let app = LookbookUITestSupport.launchApp(failureArgument: "--uitest-brand-request-failure")
        let search = app.textFields["브랜드 검색"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("없는브랜드")
        let entry = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.brandRequest.entry")
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let url = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.brandRequest.websiteURL")
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.tap()
        url.typeText("https://newbrand.example\n")
        let submit = app.buttons["요청하기"]
        if !submit.isHittable { app.swipeUp() }
        submit.tap()
        let progress = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.brandRequest.submitting")
        XCTAssertTrue(progress.waitForExistence(timeout: 2))
        let alert = app.alerts["브랜드 요청 안내"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        XCTAssertTrue(alert.staticTexts["접수 결과를 확인하지 못했어요. 요청 내역을 확인해 주세요."].exists)
        XCTAssertEqual(app.alerts.count, 1)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "resolvedBrandID")).firstMatch.exists)
        let receiptScreenshot = XCTAttachment(screenshot: app.screenshot())
        receiptScreenshot.name = "접수 결과 확인 불가 안내"
        receiptScreenshot.lifetime = .keepAlways
        add(receiptScreenshot)
        alert.buttons["확인"].tap()
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertEqual(url.value as? String, "https://newbrand.example")
        XCTAssertTrue(app.buttons["요청하기"].isEnabled)
        XCTAssertFalse(app.staticTexts["접수 결과를 확인하지 못했어요. 요청 내역을 확인해 주세요."].exists)
    }

    func testLeavingDuringSubmissionDoesNotReplaceAnotherScreen() {
        let app = LookbookUITestSupport.launchApp(failureArgument: "--uitest-brand-request-delayed-success")
        let search = app.textFields["브랜드 검색"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("없는브랜드")
        LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.brandRequest.entry").tap()
        let url = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.brandRequest.websiteURL")
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.tap()
        url.typeText("https://newbrand.example\n")
        let submit = app.buttons["요청하기"]
        if !submit.isHittable { app.swipeUp() }
        submit.tap()
        XCTAssertTrue(LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.brandRequest.submitting").waitForExistence(timeout: 2))
        app.buttons["뒤로 가기"].firstMatch.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let unexpectedNavigation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in app.staticTexts["브랜드 요청 상황"].exists }, object: nil)
        unexpectedNavigation.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unexpectedNavigation], timeout: 4), .completed)
        XCTAssertTrue(search.exists)
        XCTAssertFalse(url.exists)
    }

    func testHistoryPageFailureKeepsRowsAndRetriesFromLastCursor() {
        let app = LookbookUITestSupport.launchApp(failureArgument: "--uitest-brand-history-page-failure")
        let search = app.textFields["브랜드 검색"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("없는브랜드")
        let entry = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.brandRequest.entry")
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let url = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.brandRequest.websiteURL")
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.tap()
        url.typeText("https://newbrand.example\n")
        let submit = app.buttons["요청하기"]
        if !submit.isHittable { app.swipeUp() }
        submit.tap()
        XCTAssertTrue(app.staticTexts["브랜드 요청 상황"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["내 요청 내역 보기"].exists)
        let retry = app.buttons["다시 시도"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["요청 접수"].exists)
        XCTAssertTrue(app.staticTexts["요청 내역을 한 번에 불러오지 못했어요. 잠시 후 다시 시도해 주세요."].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "페이지 실패에서 받은 요청 유지"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        retry.tap()
        XCTAssertTrue(app.staticTexts["처리 중"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["요청 접수"].exists)
        XCTAssertFalse(retry.exists)
    }

    func testInterestRetryCentersButtonAndReplacesErrorWithLoading() {
        let app = LookbookUITestSupport.launchApp(failureArgument: "--uitest-lookbook-interest-failure")
        let failure = app.staticTexts["관심 스타일 브랜드를 불러오지 못했어요"]
        XCTAssertTrue(failure.waitForExistence(timeout: 10))
        XCTAssertEqual(failure.frame.midX, app.frame.midX, accuracy: 2)
        let retry = app.buttons["lookbook.interest.retry"]
        XCTAssertTrue(retry.exists)
        XCTAssertEqual(retry.frame.midX, app.frame.midX, accuracy: 2)
        let failureCenterY = retry.frame.midY
        let failureScreenshot = XCTAttachment(screenshot: app.screenshot())
        failureScreenshot.name = "관심 스타일 중앙 재시도"
        failureScreenshot.lifetime = .keepAlways
        add(failureScreenshot)

        retry.tap()
        let loading = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.interest.loading")
        XCTAssertTrue(loading.waitForExistence(timeout: 2))
        XCTAssertFalse(failure.exists)
        XCTAssertFalse(retry.exists)
        XCTAssertEqual(loading.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertTrue(loading.label.contains("취향에 맞는 브랜드를 찾고 있어요"))
        let loadingScreenshot = XCTAttachment(screenshot: app.screenshot())
        loadingScreenshot.name = "관심 스타일 오류를 대체한 조회 중 표시"
        loadingScreenshot.lifetime = .keepAlways
        add(loadingScreenshot)

        XCTAssertTrue(failure.waitForExistence(timeout: 8))
        XCTAssertFalse(loading.exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "관심 스타일 브랜드를 불러오지 못했어요").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "다시 시도").count, 1)
        XCTAssertEqual(retry.frame.midY, failureCenterY, accuracy: 2)
    }

    func testInterestUnconfiguredEmptyAndFailureAreDistinct() {
        let guidance = "마이페이지에서 관심 스타일을 등록해 보세요"
        let empty = "아직 관심 스타일에 맞는 브랜드가 없어요"
        let failure = "관심 스타일 브랜드를 불러오지 못했어요"
        for (argument, message) in [
            ("--uitest-lookbook-no-style-preference", guidance),
            ("--uitest-lookbook-interest-empty", empty),
            ("--uitest-lookbook-interest-failure", failure)
        ] {
            let app = LookbookUITestSupport.launchApp(failureArgument: argument)
            XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts.matching(identifier: message).count, 1)
            XCTAssertEqual(app.buttons.matching(identifier: "다시 시도").count, message == failure ? 1 : 0)
            XCTAssertFalse(app.staticTexts["관심 스타일을 불러오지 못했어요"].exists)
            for other in [guidance, empty, failure] where other != message {
                XCTAssertFalse(app.staticTexts[other].exists)
            }
        }
    }
}
