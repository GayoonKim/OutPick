import XCTest

final class BrandLocalUISimulatorTests: XCTestCase {
    #if !targetEnvironment(simulator)
    func testDeviceCompletedRequestAndPublishedImagesWithoutWrites() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ImageLoadingBaseline"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 5) {
            let text = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
            XCTAssertTrue(text.contains("로컬 네트워크") || text.localizedCaseInsensitiveContains("local network"))
            let allow = alert.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "허용", "Allow")).firstMatch
            XCTAssertTrue(allow.exists)
            allow.tap()
        }
        XCTAssertTrue(app.staticTexts["등록 완료"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["공용로컬브랜드"].firstMatch.exists)
        capture(app, "device-01-history-added")
        app.buttons["lookbook.brandRequest.openBrand"].firstMatch.tap()
        let season = app.buttons["lookbook.season.card"].firstMatch
        XCTAssertTrue(season.waitForExistence(timeout: 25))
        let loaded = app.descendants(matching: .any).matching(identifier: "lookbook.asset.loaded")
        XCTAssertTrue(loaded.firstMatch.waitForExistence(timeout: 25))
        capture(app, "device-02-brand-season-cover")
        season.tap()
        let posts = app.buttons.matching(identifier: "lookbook.post.card")
        XCTAssertTrue(posts.firstMatch.waitForExistence(timeout: 25))
        XCTAssertEqual(posts.count, 2)
        let thumbnails = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in loaded.count >= 2 }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [thumbnails], timeout: 25), .completed)
        capture(app, "device-03-season-post-images")
        for index in 0..<2 {
            posts.element(boundBy: index).tap()
            XCTAssertTrue(loaded.firstMatch.waitForExistence(timeout: 20))
            capture(app, "device-post-\(index)-detail")
            loaded.firstMatch.tap()
            let close = app.buttons["닫기"].firstMatch
            XCTAssertTrue(close.waitForExistence(timeout: 15))
            let save = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "저장")).firstMatch
            let original = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in save.exists && save.isEnabled }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [original], timeout: 25), .completed)
            capture(app, "device-post-\(index)-original")
            close.tap()
            XCTAssertTrue(loaded.firstMatch.waitForExistence(timeout: 10))
            app.buttons["뒤로 가기"].firstMatch.tap()
            XCTAssertTrue(posts.firstMatch.waitForExistence(timeout: 10))
        }
        capture(app, "device-04-returned-to-season")
        // 사진 저장/신고/좋아요는 누르지 않는다. 다운로드 원본은 앱 진단과 별도 대조한다.
    }
    #endif

    func testLocalPostsOpenOriginalImagesAndReturnWithoutWrites() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        let keys = ["OUTPICK_BRAND_LOCAL_TARGET", "OUTPICK_BRAND_LOCAL_STORAGE_TARGET", "OUTPICK_BRAND_LOCAL_LOGIN", "OUTPICK_BRAND_LOCAL_OUTPUT"]
        guard keys.allSatisfy({ environment[$0] != nil }),
              let brandName = environment["OUTPICK_BRAND_LOCAL_UI_BRAND_NAME"], !brandName.isEmpty,
              let output = environment["OUTPICK_BRAND_LOCAL_OUTPUT"] else {
            XCTFail("현재 Backend 로컬 연결 경로와 기대 브랜드명이 필요합니다.")
            return
        }
        let app = XCUIApplication()
        app.launchArguments = ["-ImageLoadingBaseline"]
        app.launchEnvironment = Dictionary(uniqueKeysWithValues: keys.map { ($0, environment[$0]!) })
        app.launchEnvironment["OUTPICK_BRAND_LOCAL_UI"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts[brandName].firstMatch.waitForExistence(timeout: 30))
        app.buttons["lookbook.brandRequest.openBrand"].firstMatch.tap()
        let season = app.buttons["lookbook.season.card"].firstMatch
        XCTAssertTrue(season.waitForExistence(timeout: 20))
        season.tap()
        let posts = app.buttons.matching(identifier: "lookbook.post.card")
        XCTAssertTrue(posts.firstMatch.waitForExistence(timeout: 20))
        XCTAssertEqual(posts.count, 2)

        for index in 0..<2 {
            posts.element(boundBy: index).tap()
            let hero = app.descendants(matching: .any).matching(identifier: "lookbook.asset.loaded").firstMatch
            XCTAssertTrue(hero.waitForExistence(timeout: 20))
            XCTAssertTrue(app.buttons["lookbook.post.likeButton"].firstMatch.exists)
            capture(app, "post-\(index)-detail")
            hero.tap()
            let close = app.buttons["닫기"].firstMatch
            XCTAssertTrue(close.waitForExistence(timeout: 15))
            let originalReceived = NSPredicate { _, _ in
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: output)),
                      let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let events = value["events"] as? [[String: Any]] else { return false }
                let paths = events.filter { ["storage.download", "storage.downloadFile"].contains($0["kind"] as? String ?? "") }
                    .compactMap { $0["path"] as? String }.filter { $0.hasSuffix("/detail.jpg") }
                let decoded = events.filter { ["image.decoded", "image.fileDecoded"].contains($0["kind"] as? String ?? "") && $0["success"] as? Bool == true }
                return Set(paths).count >= index + 1 && decoded.count >= index + 4
            }
            let received = XCTNSPredicateExpectation(predicate: originalReceived, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [received], timeout: 20), .completed)
            XCTAssertFalse(app.buttons["불러오지 못했어요 · 다시 시도"].firstMatch.exists)
            capture(app, "post-\(index)-original-viewer")
            close.tap()
            XCTAssertTrue(hero.waitForExistence(timeout: 10))
            app.buttons["뒤로 가기"].firstMatch.tap()
            XCTAssertTrue(posts.firstMatch.waitForExistence(timeout: 10))
        }
        capture(app, "posts-returned-to-season")
    }

    func testCompletedRequestShowsLocalPublishedImages() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        let keys = ["OUTPICK_BRAND_LOCAL_TARGET", "OUTPICK_BRAND_LOCAL_STORAGE_TARGET", "OUTPICK_BRAND_LOCAL_LOGIN", "OUTPICK_BRAND_LOCAL_OUTPUT"]
        guard keys.allSatisfy({ environment[$0] != nil }),
              let brandName = environment["OUTPICK_BRAND_LOCAL_UI_BRAND_NAME"], !brandName.isEmpty else {
            XCTFail("Backend의 현재 로컬 연결 경로와 기대 브랜드명이 필요합니다.")
            return
        }
        let app = XCUIApplication()
        app.launchArguments = ["-ImageLoadingBaseline"]
        app.launchEnvironment = Dictionary(uniqueKeysWithValues: keys.map { ($0, environment[$0]!) })
        app.launchEnvironment["OUTPICK_BRAND_LOCAL_UI"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["등록 완료"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts[brandName].firstMatch.exists)
        capture(app, "01-actual-request-history")
        let open = app.buttons["lookbook.brandRequest.openBrand"].firstMatch
        XCTAssertTrue(open.exists)
        open.tap()
        let season = app.buttons["lookbook.season.card"].firstMatch
        XCTAssertTrue(season.waitForExistence(timeout: 20))
        let images = app.descendants(matching: .any).matching(identifier: "lookbook.asset.loaded")
        XCTAssertTrue(images.firstMatch.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["이미지 다시 시도"].firstMatch.exists)
        capture(app, "02-actual-brand-and-season-cover")
        season.tap()
        let post = app.buttons["lookbook.post.card"].firstMatch
        XCTAssertTrue(post.waitForExistence(timeout: 20))
        let loaded = NSPredicate { _, _ in images.count >= 2 }
        expectation(for: loaded, evaluatedWith: app)
        waitForExpectations(timeout: 20)
        XCTAssertFalse(app.buttons["이미지 다시 시도"].firstMatch.exists)
        capture(app, "03-actual-season-and-lookbook-images")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
