import XCTest

/// 기존 Development 방을 읽는 실기기 QA. 메시지 전송·삭제·서버 fixture를 만들지 않는다.
final class ChatMediaViewportDevelopmentUITests: XCTestCase {
    func testPhotoPickerCancellationAndRotationRestoreMedia() throws {
        guard ProcessInfo.processInfo.environment["OUTPICK_MEDIA_VIEWPORT_QA"] == "1" else {
            throw XCTSkip("실기기 Development 미디어 QA 명시 실행 전용")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ImageLoadingBaseline", "-ChatMediaViewportQA"]
        app.launch()
        XCTAssertTrue(app.otherElements["app.main.root"].waitForExistence(timeout: 90))
        app.tabBars.buttons["채팅"].tap()
        let room = app.cells.containing(.staticText, identifier: "미디어 QA").firstMatch
        XCTAssertTrue(room.waitForExistence(timeout: 30))
        room.tap()
        let messages = app.collectionViews["chat.messages.mIWx69f7sfwWdWXkWWqR"]
        XCTAssertTrue(messages.waitForExistence(timeout: 30))
        assertVisibleMediaLoaded(app)
        app.buttons["attachmentButton"].tap()
        app.buttons["photo"].tap()
        capture(app, name: "사진 선택 화면")
        let cancel = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "취소", "Cancel")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        cancel.tap()
        XCTAssertTrue(messages.waitForExistence(timeout: 15))
        assertVisibleMediaLoaded(app)
        capture(app, name: "사진 선택 취소 복귀")

        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 10), .completed)
        assertVisibleMediaLoaded(app)
        capture(app, name: "가로 회전")
        XCUIDevice.shared.orientation = .portrait
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.height > app.frame.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 10), .completed)
        assertVisibleMediaLoaded(app)
        capture(app, name: "세로 복귀")
    }

    func testKeyboardSettingsSearchAndCancelledBackRestoreMedia() throws {
        guard ProcessInfo.processInfo.environment["OUTPICK_MEDIA_VIEWPORT_QA"] == "1" else {
            throw XCTSkip("실기기 Development 미디어 QA 명시 실행 전용")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ImageLoadingBaseline", "-ChatMediaViewportQA"]
        app.launch()
        XCTAssertTrue(app.otherElements["app.main.root"].waitForExistence(timeout: 90))
        app.tabBars.buttons["채팅"].tap()
        let room = app.cells.containing(.staticText, identifier: "미디어 QA").firstMatch
        XCTAssertTrue(room.waitForExistence(timeout: 30))
        room.tap()
        let messages = app.collectionViews["chat.messages.mIWx69f7sfwWdWXkWWqR"]
        XCTAssertTrue(messages.waitForExistence(timeout: 30))
        assertVisibleMediaLoaded(app)

        app.textViews.firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        capture(app, name: "키보드 표시")
        // 메시지 전송 없이 검색 모드의 취소 동작으로 키보드를 닫는다.
        app.buttons["Search"].tap()
        XCTAssertTrue(app.textFields["대화내용 검색"].waitForExistence(timeout: 10))
        app.buttons["취소"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
        assertVisibleMediaLoaded(app)
        capture(app, name: "키보드 검색 복귀")

        app.buttons["justify"].tap()
        capture(app, name: "설정 패널 표시")
        // 오른쪽70% 패널 바깥 dim 영역을 눌러 닫는다.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.45)).tap()
        XCTAssertTrue(app.buttons["justify"].isHittable)
        assertVisibleMediaLoaded(app)
        capture(app, name: "설정 패널 복귀")

        // 화면 폭의 일부만 이동하고 천천히 놓아 pop 취소 경로를 확인한다.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(messages.waitForExistence(timeout: 10))
        assertVisibleMediaLoaded(app)
        capture(app, name: "뒤로가기 제스처 취소 복귀")
    }

    private func assertVisibleMediaLoaded(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let previews = app.cells.matching(identifier: "chat.media.preview")
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            // 회전 직후 일부만 보이는 셀은 XCTest hit point 계산이 실패할 수 있다.
            // 표시 검증이므로 터치 가능 여부 대신 채팅 viewport와의 교차 영역을 사용한다.
            let viewport = app.collectionViews["chat.messages.mIWx69f7sfwWdWXkWWqR"].frame.intersection(app.frame)
            let visible = previews.allElementsBoundByIndex.filter {
                let intersection = $0.frame.intersection(viewport)
                return !intersection.isNull && intersection.width > 1 && intersection.height > 1
            }
            return !visible.isEmpty && visible.allSatisfy { ($0.value as? String) == "loaded" }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 30), .completed, file: file, line: line)
    }

    func testExistingMediaRoomScrollReentryAndBackground() throws {
        guard ProcessInfo.processInfo.environment["OUTPICK_MEDIA_VIEWPORT_QA"] == "1" else {
            throw XCTSkip("실기기 Development 미디어 QA 명시 실행 전용")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ImageLoadingBaseline", "-ChatMediaViewportQA"]
        app.launch()
        XCTAssertTrue(app.otherElements["app.main.root"].waitForExistence(timeout: 90))
        app.tabBars.buttons["채팅"].tap()
        let room = app.cells.containing(.staticText, identifier: "미디어 QA").firstMatch
        XCTAssertTrue(room.waitForExistence(timeout: 30))
        for _ in 0..<8 where !room.isHittable { app.swipeUp() }
        capture(app, name: "채팅 목록")
        XCTAssertTrue(room.waitForExistence(timeout: 15))
        room.tap()
        let messages = app.collectionViews["chat.messages.mIWx69f7sfwWdWXkWWqR"]
        XCTAssertTrue(messages.waitForExistence(timeout: 30))
        capture(app, name: "미디어 방 첫 진입")
        for _ in 0..<6 { messages.swipeDown(velocity: .slow) }
        capture(app, name: "과거 사진 묶음")
        let loadedPhoto = app.cells.matching(identifier: "chat.media.preview")
            .matching(NSPredicate(format: "value == %@", "loaded"))
        let visiblePhoto = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            loadedPhoto.allElementsBoundByIndex.contains(where: { $0.isHittable })
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visiblePhoto], timeout: 30), .completed)
        try XCTUnwrap(loadedPhoto.allElementsBoundByIndex.first(where: { $0.isHittable })).tap()
        XCTAssertTrue(app.buttons["닫기"].waitForExistence(timeout: 15))
        capture(app, name: "사진 확대")
        app.buttons["닫기"].tap()
        XCTAssertTrue(messages.waitForExistence(timeout: 15))
        for _ in 0..<3 { messages.swipeUp(); messages.swipeDown() }
        capture(app, name: "왕복 스크롤")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(messages.waitForExistence(timeout: 15))
        capture(app, name: "백그라운드 복귀")
        app.buttons["navigation.back"].tap()
        XCTAssertTrue(room.waitForExistence(timeout: 15))
        room.tap()
        XCTAssertTrue(messages.waitForExistence(timeout: 30))
        capture(app, name: "방 재진입")
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + " UI 구조"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
