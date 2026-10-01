#if DEBUG
import Foundation
import XCTest
@testable import OutPick

@MainActor
final class ChatSignedURLQAHTTPClientTests: XCTestCase {
    private let url = URL(string: "https://signed.invalid/qa?signature=synthetic")!

    func testClientBuildsHTTPSGETAndRangeAndRemovesDownloadedFiles() async throws {
        let fixture = QAURLSessionBoundary()
        let client = ChatSignedURLQAHTTPClient { try await fixture.download(session: $0, request: $1) }
        let full = try await client.get(url, range: false)
        let range = try await client.get(url, range: true)
        let requests = await fixture.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.url == url && $0.httpMethod == "GET" })
        XCTAssertTrue(requests.allSatisfy { $0.url?.scheme == "https" })
        XCTAssertTrue(requests.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
        XCTAssertTrue(requests.allSatisfy { $0.timeoutInterval == 60 })
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Range"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Range"), "bytes=0-15")
        let cacheDisabled = await fixture.cacheDisabled
        XCTAssertEqual(cacheDisabled, [true, true])
        XCTAssertEqual(full.status, 200)
        XCTAssertEqual(full.bytes, 64)
        XCTAssertEqual(range.status, 206)
        XCTAssertEqual(range.bytes, 16)
        XCTAssertEqual(range.rangeStart, 0)
        XCTAssertEqual(range.rangeEnd, 15)
        XCTAssertEqual(range.rangeTotal, full.bytes)
        await assertFilesRemoved(fixture, expected: 2)
    }

    func testClientParsesExpired403BodyWithoutConfusingOtherFailures() async throws {
        let cases: [(Int, String, Bool)] = [
            (400, "<Error><Code>ExpiredToken</Code><Message>Invalid argument.</Message><Details>Request signature expired at: synthetic</Details></Error>", true),
            (400, "<Error><Code>InvalidArgument</Code><Message>Request has expired.</Message></Error>", false),
            (400, "<Error><Code>AccessDenied</Code><Message>Request has expired.</Message></Error>", false),
            (403, "<Error><Code>ExpiredToken</Code><Message>Invalid argument.</Message></Error>", false),
            (403, "<Error><Code>AccessDenied</Code><Message>Request has expired.</Message></Error>", true),
            (403, "<Error><Code>AccessDenied</Code><Message>Access denied.</Message></Error>", false),
            (404, "<Error><Code>ExpiredToken</Code><Message>Request has expired.</Message></Error>", false),
            (500, "<Error><Code>ExpiredToken</Code></Error>", false)
        ]
        for (status, body, expected) in cases {
            let fixture = QAURLSessionBoundary(status: status, body: Data(body.utf8))
            let client = ChatSignedURLQAHTTPClient { try await fixture.download(session: $0, request: $1) }
            let response = try await client.get(url, range: true)
            XCTAssertEqual(response.status, status)
            XCTAssertEqual(response.expiredError, expected)
            XCTAssertEqual(response.errorKind.rawValue, expected ? (status == 400 ? "expiredToken" : "expiredRequest") : "other")
            await assertFilesRemoved(fixture, expected: 1)
        }
    }

    func testClientRejectsMalformedDuplicateAndNestedExpiryBodies() async throws {
        for body in [
            "<Error><Code>ExpiredToken</Code>",
            "<Error><Code>InvalidArgument</Code><Code>ExpiredToken</Code></Error>",
            "<Error><Details><Code>ExpiredToken</Code></Details></Error>",
            "<Error><Code><Value>ExpiredToken</Value></Code></Error>",
            "<Error><Code>ExpiredTokenExtra</Code></Error>",
            "<html><Code>ExpiredToken</Code></html>", "ExpiredToken", ""
        ] {
            let fixture = QAURLSessionBoundary(status: 400, body: Data(body.utf8))
            let client = ChatSignedURLQAHTTPClient { try await fixture.download(session: $0, request: $1) }
            let response = try await client.get(url, range: true)
            XCTAssertEqual(response.errorKind, .other)
            XCTAssertFalse(response.expiredError)
            await assertFilesRemoved(fixture, expected: 1)
        }
    }

    func testClientEnforcesErrorBodyLimitAndRejectsEntityDeclarations() async throws {
        let prefix = "<Error><Code>ExpiredToken</Code><Details>"
        let suffix = "</Details></Error>"
        let boundary = prefix + String(repeating: "a", count: 65536 - prefix.utf8.count - suffix.utf8.count) + suffix
        for (body, expected) in [
            (boundary, true), (boundary + " ", false),
            ("<!DOCTYPE Error [<!ENTITY code 'ExpiredToken'>]><Error><Code>&code;</Code></Error>", false)
        ] {
            let fixture = QAURLSessionBoundary(status: 400, body: Data(body.utf8))
            let client = ChatSignedURLQAHTTPClient { try await fixture.download(session: $0, request: $1) }
            let response = try await client.get(url, range: true)
            XCTAssertEqual(response.expiredError, expected)
            await assertFilesRemoved(fixture, expected: 1)
        }
    }

    func testClientRemovesFileWhenResponseIsNotHTTP() async throws {
        let fixture = QAURLSessionBoundary(nonHTTP: true)
        let client = ChatSignedURLQAHTTPClient { try await fixture.download(session: $0, request: $1) }
        do {
            _ = try await client.get(url, range: false)
            XCTFail("HTTP가 아닌 응답 허용")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
        }
        await assertFilesRemoved(fixture, expected: 1)
    }

    func testClientPropagatesTransportFailureWithoutProducingResponse() async throws {
        let client = ChatSignedURLQAHTTPClient { _, _ in throw URLError(.timedOut) }
        do {
            _ = try await client.get(url, range: true)
            XCTFail("전송 실패를 응답으로 처리")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
    }

    func testCancelledProbeRemovesLateFileThroughConcreteHTTPClient() async throws {
        let started = expectation(description: "임시 파일 생성 뒤 응답 대기")
        let cancelled = expectation(description: "늦은 파일 정리 뒤 관측 취소")
        let fixture = QAURLSessionBoundary(delayed: true, onStarted: { started.fulfill() })
        let client = ChatSignedURLQAHTTPClient { try await fixture.download(session: $0, request: $1) }
        var events: [ChatSignedURLQARecord] = []
        let qa = ChatSignedURLHTTPQA(messageID: "test", http: client, record: {
            events.append($0)
            if $0.event == "cancelled" { cancelled.fulfill() }
        })
        let expiry = Date().addingTimeInterval(7200)
        let resource = ChatOriginalResource(path: "rooms/MFBgh49togDCjlnPt4CM/messages/test/attachments/fixture/display",
            version: "123", mediaExpiresAt: expiry)
        let ticket = ChatMediaURLTicket(url: url, urlExpiresAt: Date().addingTimeInterval(3600),
            mediaExpiresAt: expiry, generation: "123")
        qa.observe(resource: resource, ticket: ticket)
        await fulfillment(of: [started], timeout: 2)
        qa.invalidate()
        await fixture.finish()
        await fulfillment(of: [cancelled], timeout: 2)
        await assertFilesRemoved(fixture, expected: 1)
        XCTAssertFalse(events.contains { $0.event == "get" || ($0.event == "complete" && $0.passed) })
    }

    private func assertFilesRemoved(_ fixture: QAURLSessionBoundary, expected: Int) async {
        let files = await fixture.files
        defer { files.forEach { try? FileManager.default.removeItem(at: $0) } }
        XCTAssertEqual(files.count, expected)
        XCTAssertTrue(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }
}

/// 실제 클라이언트의 요청·해석·정리는 실행하고 URLSession 전송 경계만 합성 파일로 제어한다.
private actor QAURLSessionBoundary {
    private(set) var requests: [URLRequest] = []
    private(set) var files: [URL] = []
    private(set) var cacheDisabled: [Bool] = []
    private let status: Int?
    private let body: Data?
    private let nonHTTP: Bool
    private let delayed: Bool
    private let onStarted: (@Sendable () -> Void)?
    private var pending: CheckedContinuation<Void, Never>?

    init(status: Int? = nil, body: Data? = nil, nonHTTP: Bool = false,
         delayed: Bool = false, onStarted: (@Sendable () -> Void)? = nil) {
        self.status = status; self.body = body; self.nonHTTP = nonHTTP
        self.delayed = delayed; self.onStarted = onStarted
    }

    func download(session: URLSession, request: URLRequest) async throws -> (URL, URLResponse) {
        requests.append(request)
        cacheDisabled.append(session.configuration.urlCache == nil)
        let range = request.value(forHTTPHeaderField: "Range") != nil
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try (body ?? Data(repeating: 7, count: range ? 16 : 64)).write(to: file)
        files.append(file)
        if delayed {
            await withCheckedContinuation { pending = $0; onStarted?() }
        } else { onStarted?() }
        let response: URLResponse
        if nonHTTP {
            response = URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 64, textEncodingName: nil)
        } else {
            response = HTTPURLResponse(url: request.url!, statusCode: status ?? (range ? 206 : 200),
                httpVersion: "HTTP/1.1", headerFields: range && status == nil ? ["Content-Range": "bytes 0-15/64"] : [:])!
        }
        return (file, response)
    }

    func finish() { pending?.resume(); pending = nil }
}
#endif
