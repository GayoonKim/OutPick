#if DEBUG
import Foundation
import XCTest
@testable import OutPick

@MainActor
final class ChatSignedURLHTTPQATests: XCTestCase {
    func testRangeParserRejectsMalformedOrImpossibleBounds() {
        XCTAssertEqual(ChatSignedURLQAHTTPClient.bounds("bytes 0-15/100")?.2, 100)
        for header in ["bytes */100", "bytes 16-15/100", "bytes 0-15/15", "bytes -1-15/100", "secret"] {
            XCTAssertNil(ChatSignedURLQAHTTPClient.bounds(header))
        }
    }

    func testExpiryProbeUsesSameTicketAndRequiresRangeAndExpiredReason() async throws {
        var now = Date()
        let deadline = now.addingTimeInterval(3600)
        let http = QAHTTPSpy(responses: [full, range, expired])
        var events: [(String, Bool)] = []
        let completed = expectation(description: "만료 판정 완료")
        let qa = ChatSignedURLHTTPQA(messageID: "test", http: http, now: { now }, sleep: { seconds in
            XCTAssertGreaterThanOrEqual(seconds, 3600)
            now = now.addingTimeInterval(seconds)
        }, record: {
            events.append(($0.event, $0.passed))
            if $0.event == "complete" { completed.fulfill() }
        })
        let (resource, ticket) = try fixture(deadline: deadline)
        qa.observe(resource: resource, ticket: ticket)
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(http.ranges, [false, true, true])
        XCTAssertTrue(http.urls.allSatisfy { $0 == ticket.url })
        XCTAssertTrue(events.contains { $0.0 == "complete" && $0.1 })
    }

    func testPermission403CannotPassAsExpiredURL() async throws {
        var now = Date()
        let http = QAHTTPSpy(responses: [full, range,
            ChatSignedURLQAResponse(status: 403, bytes: 10, rangeStart: nil, rangeEnd: nil, rangeTotal: nil)])
        var events: [(String, Bool)] = []
        let completed = expectation(description: "권한403 판정 완료")
        let qa = ChatSignedURLHTTPQA(messageID: "test", http: http, now: { now },
            sleep: { now = now.addingTimeInterval($0) }, record: {
                events.append(($0.event, $0.passed))
                if $0.event == "complete" { completed.fulfill() }
            })
        let (resource, ticket) = try fixture(deadline: now.addingTimeInterval(30))
        qa.observe(resource: resource, ticket: ticket)
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertTrue(events.contains { $0.0 == "expired" && !$0.1 })
        XCTAssertFalse(events.contains { $0.0 == "complete" && $0.1 })
    }

    func testOrdinary400AndMismatchedErrorKindCannotPassAsExpiredURL() async throws {
        for (status, kind) in [(400, ChatMediaHTTPErrorKind.other), (403, .expiredToken), (500, .expiredToken)] {
            var now = Date()
            let http = QAHTTPSpy(responses: [full, range,
                .init(status: status, bytes: 10, rangeStart: nil, rangeEnd: nil, rangeTotal: nil, errorKind: kind)])
            var completedPassed: Bool?
            let completed = expectation(description: "만료 외 오류 판정 완료")
            let qa = ChatSignedURLHTTPQA(messageID: "test", http: http, now: { now },
                sleep: { now = now.addingTimeInterval($0) }, record: {
                    if $0.event == "complete" { completedPassed = $0.passed; completed.fulfill() }
                })
            let (resource, ticket) = try fixture(deadline: now.addingTimeInterval(30))
            qa.observe(resource: resource, ticket: ticket)
            await fulfillment(of: [completed], timeout: 2)
            XCTAssertEqual(completedPassed, false)
        }
    }

    func testInvalidRangeStopsBeforeExpiryAndOtherMessageDoesNotStart() async throws {
        let now = Date()
        let http = QAHTTPSpy(responses: [full, full])
        var events: [(String, Bool)] = []
        let completed = expectation(description: "잘못된 Range 중단")
        let qa = ChatSignedURLHTTPQA(messageID: "test", http: http, now: { now },
            sleep: { _ in XCTFail("잘못된 Range 응답 뒤 만료 대기") }, record: {
                events.append(($0.event, $0.passed))
                if $0.event == "incomplete" { completed.fulfill() }
            })
        let (resource, ticket) = try fixture(deadline: now.addingTimeInterval(30))
        let other = ChatOriginalResource(path: resource.path.replacingOccurrences(of: "/test/", with: "/other/"),
            version: "123", mediaExpiresAt: ticket.mediaExpiresAt)
        qa.observe(resource: other, ticket: ticket)
        XCTAssertTrue(events.isEmpty)
        qa.observe(resource: resource, ticket: ticket)
        qa.observe(resource: resource, ticket: ticket)
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(http.urls.count, 2)
        XCTAssertTrue(events.contains { $0.0 == "incomplete" && !$0.1 })
    }

    func testAccountInvalidationCancelsDelayedHTTPWithoutPassing() async throws {
        let now = Date()
        let http = QAHTTPSpy(responses: [full])
        http.delayed = true
        var events: [(String, Bool)] = []
        let started = expectation(description: "HTTP 응답 대기 시작")
        let cancelled = expectation(description: "계정 종료 후 늦은 응답 거절")
        http.onStarted = { started.fulfill() }
        let qa = ChatSignedURLHTTPQA(messageID: "test", http: http,
            record: {
                events.append(($0.event, $0.passed))
                if $0.event == "cancelled" { cancelled.fulfill() }
            })
        let (resource, ticket) = try fixture(deadline: now.addingTimeInterval(30))
        qa.observe(resource: resource, ticket: ticket)
        await fulfillment(of: [started], timeout: 2)
        qa.invalidate()
        http.finish()
        await fulfillment(of: [cancelled], timeout: 2)
        XCTAssertEqual(http.urls.count, 1)
        XCTAssertTrue(events.contains { $0.0 == "cancelled" && !$0.1 })
        XCTAssertFalse(events.contains { $0.0 == "complete" && $0.1 })
    }

    private var full: ChatSignedURLQAResponse {
        .init(status: 200, bytes: 100, rangeStart: nil, rangeEnd: nil, rangeTotal: nil)
    }
    private var range: ChatSignedURLQAResponse {
        .init(status: 206, bytes: 16, rangeStart: 0, rangeEnd: 15, rangeTotal: 100)
    }
    private var expired: ChatSignedURLQAResponse {
        .init(status: 400, bytes: 10, rangeStart: nil, rangeEnd: nil, rangeTotal: nil, errorKind: .expiredToken)
    }
    private func fixture(deadline: Date) throws -> (ChatOriginalResource, ChatMediaURLTicket) {
        let expiry = deadline.addingTimeInterval(3600)
        return (ChatOriginalResource(path: "rooms/MFBgh49togDCjlnPt4CM/messages/test/attachments/fixture/display",
            version: "123", mediaExpiresAt: expiry),
            ChatMediaURLTicket(url: URL(string: "https://signed.invalid/secret")!,
                urlExpiresAt: deadline, mediaExpiresAt: expiry, generation: "123"))
    }

    func testQARequiresDevelopmentProjectFlagAndNonemptyMessage() {
        let info = ["OUTPICK_ENVIRONMENT": "development", "OUTPICK_EXPECTED_FIREBASE_PROJECT_ID": "outpick-test"]
        let env = ["OUTPICK_SIGNED_HTTP_QA": "1", "OUTPICK_SIGNED_HTTP_QA_MESSAGE": "test"]
        XCTAssertNotNil(ChatSignedURLHTTPQA.enabledForCurrentProcess(info: info, env: env))
        for values in [[:], ["OUTPICK_ENVIRONMENT": "production", "OUTPICK_EXPECTED_FIREBASE_PROJECT_ID": "outpick-test"],
                       ["OUTPICK_ENVIRONMENT": "development", "OUTPICK_EXPECTED_FIREBASE_PROJECT_ID": "outpick-664ae"]] {
            XCTAssertNil(ChatSignedURLHTTPQA.enabledForCurrentProcess(info: values, env: env))
        }
        for values in [[:], ["OUTPICK_SIGNED_HTTP_QA": "0", "OUTPICK_SIGNED_HTTP_QA_MESSAGE": "test"],
                       ["OUTPICK_SIGNED_HTTP_QA": "1"],
                       ["OUTPICK_SIGNED_HTTP_QA": "1", "OUTPICK_SIGNED_HTTP_QA_MESSAGE": ""]] {
            XCTAssertNil(ChatSignedURLHTTPQA.enabledForCurrentProcess(info: info, env: values))
        }
    }

    func testServiceInvalidationCancelsQAThroughTicketObservation() async throws {
        try await assertServiceCancellation(deleteTarget: false)
    }

    func testServiceTargetRemovalCancelsQAButOtherRemovalDoesNot() async throws {
        try await assertServiceCancellation(deleteTarget: true)
    }

    private func assertServiceCancellation(deleteTarget: Bool) async throws {
        let now = Date()
        let (resource, ticket) = try fixture(deadline: now.addingTimeInterval(30))
        let http = QAHTTPSpy(responses: [full])
        http.delayed = true
        let started = expectation(description: "서비스가 관측기 시작")
        let cancelled = expectation(description: "서비스가 관측기 취소")
        http.onStarted = { started.fulfill() }
        var events: [ChatSignedURLQARecord] = []
        let qa = ChatSignedURLHTTPQA(messageID: "test", http: http, record: {
            events.append($0)
            if $0.event == "cancelled" { cancelled.fulfill() }
        })
        let service = ChatMediaSignedDownloadService(repository: QATicketRepository(ticket: ticket), now: { now })
        service.httpQA = qa
        _ = try await service.ticket(for: resource)
        await fulfillment(of: [started], timeout: 2)
        if deleteTarget {
            service.remove(path: resource.path + "-other")
            let before = events.filter { $0.event == "ticketObserved" }.count
            _ = try await service.ticket(for: resource)
            XCTAssertEqual(events.filter { $0.event == "ticketObserved" }.count, before + 1)
            XCTAssertFalse(events.contains { $0.event == "cancelled" })
            service.remove(path: resource.path)
        } else {
            service.invalidateSession()
        }
        http.finish()
        await fulfillment(of: [cancelled], timeout: 2)
        XCTAssertEqual(http.urls.count, 1)
        XCTAssertFalse(events.contains { $0.event == "complete" && $0.passed })
        let observed = events.count
        qa.observe(resource: resource, ticket: ticket)
        XCTAssertEqual(events.count, observed)
    }
}

@MainActor
private final class QAHTTPSpy: ChatSignedURLQAHTTP, @unchecked Sendable {
    var urls: [URL] = []
    var ranges: [Bool] = []
    var delayed = false
    var onStarted: (() -> Void)?
    private let responses: [ChatSignedURLQAResponse]
    private var pending: CheckedContinuation<Void, Never>?
    init(responses: [ChatSignedURLQAResponse]) { self.responses = responses }
    func get(_ url: URL, range: Bool) async throws -> ChatSignedURLQAResponse {
        urls.append(url); ranges.append(range)
        if delayed {
            await withCheckedContinuation { pending = $0; onStarted?() }
        } else { onStarted?() }
        return responses[min(urls.count - 1, responses.count - 1)]
    }
    func finish() { pending?.resume(); pending = nil }
}

private struct QATicketRepository: ChatMediaURLRepository {
    let ticket: ChatMediaURLTicket
    func issue(_ request: ChatMediaURLRequest) async throws -> ChatMediaURLTicket { ticket }
}
#endif
