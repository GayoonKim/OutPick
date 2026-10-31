import XCTest

/// Development 관리자 계정으로 브랜드 생성과 시즌 후보 탐색까지만 확인합니다.
/// 후보 목록이 fixture와 다르면 시즌 선택·이미지 import는 제출하지 않습니다.
final class LookbookImportQ7DevelopmentUITests: XCTestCase {
    private let expectedCandidateTitles = [
        "campaign UNAFFECTED FALL-WINTER 2026 INTERSTICE",
        "campaign UNAFFECTED SPRING-SUMMER 2026 INTERSTICE",
        "campaign UNAFFECTED FALL-WINTER 2025 INTERSTICE",
        "campaign UNAFFECTED SPRING-SUMMER 2025 Sensory Expansion©",
        "campaign UNAFFECTED FALL-WINTER 2024",
        "campaign UNAFFECTED SPRING-SUMMER 2024"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        try requireDevelopmentUITestOptIn()
    }

    func testCreateQABrandAndDiscoverCandidatesWithoutImport() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Q7 Development UI 검증은 실제 iPhone에서만 실행합니다.")
        #endif

        guard let runID = environmentValue("OUTPICK_Q7_RUN_ID"),
              runID.range(of: "^[A-Za-z0-9-]{8,32}$", options: .regularExpression) != nil else {
            throw XCTSkip("중복 QA 브랜드를 막기 위해 OUTPICK_Q7_RUN_ID가 필요합니다.")
        }

        let brandName = "Q7-A-\(runID)"
        let app = XCUIApplication()
        app.launch()

        let lookbookTab = app.tabBars.buttons["룩북"]
        XCTAssertTrue(lookbookTab.waitForExistence(timeout: 60), "실제 로그인 세션의 룩북 탭이 표시되어야 합니다.")
        lookbookTab.tap()

        let adminButton = app.buttons["Lookbook 관리자"]
        XCTAssertTrue(
            adminButton.waitForExistence(timeout: 60),
            "실제 Development 앱에서 총 관리자 화면에 접근할 수 있어야 합니다. 이 검사 전에는 원격 쓰기를 하지 않습니다."
        )
        adminButton.tap()

        let addBrandButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "브랜드 추가")
        ).firstMatch
        XCTAssertTrue(addBrandButton.waitForExistence(timeout: 15), "관리자 콘솔에서 브랜드 추가를 찾지 못했습니다.")
        addBrandButton.tap()

        fillField(placeholder: "예: 언어팩티드", value: brandName, in: app)
        fillField(placeholder: "예: UNAFFECTED", value: brandName, in: app)
        fillField(placeholder: "https://www.example.com", value: "https://unaffected.co.kr", in: app)
        fillField(
            placeholder: "https://www.example.com/collections",
            value: "https://unaffected.co.kr/collection.html?cate_no=88",
            in: app
        )

        let createButton = app.buttons["브랜드 생성"]
        scrollToHittable(createButton, in: app)
        XCTAssertTrue(createButton.isHittable, "브랜드 생성 버튼을 누를 수 있어야 합니다.")
        createButton.tap()

        let candidateHeader = app.staticTexts["선택할 시즌"]
        XCTAssertTrue(
            candidateHeader.waitForExistence(timeout: 300),
            "브랜드 생성 후 시즌 후보 화면에 도달하지 못했습니다. 이미지 import는 제출하지 않았습니다."
        )

        for title in expectedCandidateTitles {
            XCTAssertTrue(
                candidateButton(containing: title, in: app).waitForExistence(timeout: 30),
                "고정 fixture의 후보 제목을 찾지 못했습니다: \(title). 이미지 import는 제출하지 않았습니다."
            )
        }

        let actualCandidateTitles = app.buttons.allElementsBoundByIndex.compactMap { button in
            expectedCandidateTitles.first(where: { button.label.contains($0) })
        }
        let candidateEvidence = [
            "runID: \(runID)",
            "brandName: \(brandName)",
            "fixtureDigest: c4fb65f71fa5f26a6f9a531e58b8629ba2aff0f612c81e75e7cdeb05028f0c56",
            "expectedCandidateTitles:",
            expectedCandidateTitles.joined(separator: "\n"),
            "observedCandidateButtonTitles:",
            actualCandidateTitles.joined(separator: "\n"),
            "selectedCount: 0",
            "imageImportSubmitted: false"
        ].joined(separator: "\n")

        let textAttachment = XCTAttachment(string: candidateEvidence)
        textAttachment.name = "Q7 후보 목록 증거"
        textAttachment.lifetime = .keepAlways
        add(textAttachment)

        let screenshotAttachment = XCTAttachment(screenshot: app.screenshot())
        screenshotAttachment.name = "Q7 후보 선택 화면"
        screenshotAttachment.lifetime = .keepAlways
        add(screenshotAttachment)

        XCTAssertEqual(
            actualCandidateTitles,
            expectedCandidateTitles,
            "후보 수·순서·제목이 고정 fixture와 다르면 이미지 import를 진행하지 않습니다."
        )
        XCTAssertTrue(app.staticTexts["0/6개 선택됨"].exists, "후보는 선택되지 않은 상태여야 합니다.")
        XCTAssertTrue(app.buttons["브랜드 등록 마치기"].exists, "이미지 import 제출 버튼을 누르지 않은 상태여야 합니다.")
    }

    private func requireDevelopmentUITestOptIn() throws {
        guard environmentValue("OUTPICK_Q7_DEVELOPMENT_UI_TEST") == "1" else {
            throw XCTSkip("OUTPICK_Q7_DEVELOPMENT_UI_TEST=1로 명시한 실기기 Q7 검증에서만 실행합니다.")
        }
        guard environmentValue("OUTPICK_Q7_RUN_ID") != nil else {
            throw XCTSkip("중복 QA 브랜드를 막기 위해 OUTPICK_Q7_RUN_ID가 필요합니다.")
        }
    }

    private func environmentValue(_ name: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        return environment[name] ?? environment["TEST_RUNNER_\(name)"]
    }

    private func fillField(
        placeholder: String,
        value: String,
        in app: XCUIApplication
    ) {
        let field = app.textFields[placeholder]
        XCTAssertTrue(field.waitForExistence(timeout: 20), "입력 항목을 찾지 못했습니다: \(placeholder)")
        scrollToHittable(field, in: app)
        XCTAssertTrue(field.isHittable, "입력 항목을 누를 수 없습니다: \(placeholder)")
        field.tap()
        field.typeText(value)
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<6 where element.isHittable == false {
            guard scrollView.exists else { return }
            scrollView.swipeUp()
        }
    }

    private func candidateButton(containing title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }
}
