//
//  LookbookTestFirebaseUITests.swift
//  OutPickUITests
//
//  Created by Codex on 5/20/26.
//

import XCTest

final class LookbookTestFirebaseUITests: XCTestCase {
    private var testAdminServer: LookbookTestAdminServerClient!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try LookbookUITestSupport.requireTestFirebaseUITestOptIn()

        testAdminServer = LookbookTestAdminServerClient()
        try testAdminServer.assertHealthy()
    }

    func testSeededLookbookCommentsOpenFromTestFirebase() throws {
        try testAdminServer.reset()
        try testAdminServer.seed(.comments)

        let app = LookbookUITestSupport.launchAppUsingTestFirebase(authenticated: true)
        try LookbookUITestSupport.openCommentsSheet(in: app)

        let commentCard = LookbookUITestSupport.firstElement(in: app, identifier: "lookbook.comment.card")
        XCTAssertTrue(commentCard.waitForExistence(timeout: 10), "Test Firebase 댓글 seed를 화면에서 찾지 못했습니다.")
    }
}
