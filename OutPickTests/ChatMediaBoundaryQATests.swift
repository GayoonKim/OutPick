import XCTest
@testable import OutPick

#if DEBUG
@MainActor
final class ChatMediaBoundaryQATests: XCTestCase {
    private let message = "11111111-1111-1111-1111-111111111111"
    private func resource(_ variant: String = "display") -> ChatOriginalResource {
        .init(path: "gs://outpick-test-chat-media/rooms/\(ChatMediaBoundaryQA.roomID)/messages/\(message)/attachments/attachment/\(variant)",
              version: "123", mediaExpiresAt: Date().addingTimeInterval(7200))
    }
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testRequiresExactDevelopmentFlagModeAndRun() throws {
        let info: [String: Any] = ["OUTPICK_ENVIRONMENT": "development", "OUTPICK_EXPECTED_FIREBASE_PROJECT_ID": "outpick-test"]
        let env = ["OUTPICK_BOUNDARY_QA": "1", "OUTPICK_BOUNDARY_QA_MODE": "holdFile",
                   "OUTPICK_BOUNDARY_QA_MESSAGE": message, "OUTPICK_BOUNDARY_QA_RUN": UUID().uuidString]
        XCTAssertNotNil(ChatMediaBoundaryQA.configuration(info: info, env: env))
        for key in env.keys { var missing = env; missing[key] = "invalid"; XCTAssertNil(ChatMediaBoundaryQA.configuration(info: info, env: missing)) }
        XCTAssertNil(ChatMediaBoundaryQA.configuration(info: [:], env: env))
        XCTAssertNil(ChatMediaBoundaryQA.configuration(info: ["OUTPICK_ENVIRONMENT": "production", "OUTPICK_EXPECTED_FIREBASE_PROJECT_ID": "outpick-test"], env: env))
        XCTAssertNil(ChatMediaBoundaryQA.configuration(info: ["OUTPICK_ENVIRONMENT": "development", "OUTPICK_EXPECTED_FIREBASE_PROJECT_ID": "outpick-664ae"], env: env))
    }

    func testOnlyExactOriginalWaitsAndWrongSignalCannotRelease() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let pause = BoundaryPause(); var events: [String] = []
        let qa = try ChatMediaBoundaryQA(mode: .holdURL, messageID: message, runID: UUID(), root: root,
                                        wait: { await pause.wait() }, record: { events.append($0) })
        XCTAssertFalse(qa.matches(resource("thumbnail")))
        XCTAssertFalse(qa.matches(ChatOriginalResource(path: resource().path.replacingOccurrences(of: "outpick-test-chat-media", with: "other"))))
        XCTAssertFalse(qa.matches(ChatOriginalResource(path: resource().path.replacingOccurrences(of: message, with: UUID().uuidString))))
        let ticket = BoundaryRepository.ticket(expiry: resource().mediaExpiresAt!)
        try await qa.issued(try ChatMediaURLRequest(path: resource("thumbnail").path), ticket: ticket)
        XCTAssertFalse(events.contains { $0.contains("event=holding") })
        let first = expectation(description: "처음 보류"); pause.next = first
        let task = Task { try await qa.issued(try ChatMediaURLRequest(path: resource().path), ticket: ticket) }
        await fulfillment(of: [first], timeout: 2)
        try Data("wrong-run".utf8).write(to: qa.signal("url"))
        let second = expectation(description: "잘못된 신호 뒤에도 보류"); pause.next = second; pause.resume()
        await fulfillment(of: [second], timeout: 2)
        XCTAssertFalse(events.contains { $0.contains("event=released") })
        try Data(qa.runID.uuidString.utf8).write(to: qa.signal("url")); pause.resume()
        try await task.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: qa.signal("url").path))
        XCTAssertEqual(events.filter { $0.contains("event=released") }.count, 1)
        try await qa.issued(try ChatMediaURLRequest(path: resource().path), ticket: ticket)
        XCTAssertEqual(events.filter { $0.contains("event=holding") }.count, 1)
    }

    func testServiceNeverHoldsOtherBucketRoomMessageOrThumbnail() async throws {
        let original = resource()
        let paths = [
            original.path.replacingOccurrences(of: "outpick-test-chat-media", with: "other"),
            original.path.replacingOccurrences(of: ChatMediaBoundaryQA.roomID, with: "other-room"),
            original.path.replacingOccurrences(of: message, with: UUID().uuidString),
            resource("thumbnail").path
        ]
        for path in paths {
            let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
            var events: [String] = []
            // 잘못된 대상을 보류하면 대기 없이 실패하도록 한다.
            let qa = try ChatMediaBoundaryQA(mode: .holdURL, messageID: message, runID: UUID(), root: root,
                                            timeout: 0, record: { events.append($0) })
            let fixture = ChatOriginalResource(path: path, version: original.version,
                                               mediaExpiresAt: original.mediaExpiresAt)
            let repository = BoundaryRepository(expiry: original.mediaExpiresAt!)
            let http = BoundaryHTTP()
            let service = ChatMediaSignedDownloadService(repository: repository, http: http)
            service.boundaryQA = qa
            let destination = root.appendingPathComponent("destination")
            try await service.file(resource: fixture, maxBytes: 100, to: destination)
            XCTAssertEqual(repository.calls, 1)
            XCTAssertEqual(http.calls, 1)
            XCTAssertEqual(try Data(contentsOf: destination), Data([1, 2, 3]))
            XCTAssertTrue(http.files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
            XCTAssertFalse(events.contains { $0.contains("event=issued") || $0.contains("event=holding") })
        }
    }

    func testLateURLAfterSessionInvalidationIsRejectedWithoutDownload() async throws {
        for invalidate in [false, true] {
        let fixture = resource()
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let pause = BoundaryPause(); var events: [String] = []
        let qa = try ChatMediaBoundaryQA(mode: .holdURL, messageID: message, runID: UUID(), root: root,
                                        wait: { await pause.wait() }, record: { events.append($0) })
        let http = BoundaryHTTP(); let service = ChatMediaSignedDownloadService(repository: BoundaryRepository(expiry: fixture.mediaExpiresAt!), http: http)
        service.boundaryQA = qa
        let held = expectation(description: "실제 저장 경로 URL 보류"); pause.next = held
        let destination = root.appendingPathComponent("destination")
        let task = Task { try await service.file(resource: fixture, maxBytes: 100, to: destination) }
        await fulfillment(of: [held], timeout: 2)
        if invalidate { service.invalidateSession() } else { task.cancel() }
        try Data(qa.runID.uuidString.utf8).write(to: qa.signal("url")); pause.resume()
        do { try await task.value; XCTFail("종료 계정에 늦은 URL 허용") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(http.calls, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(events.contains { $0.contains("event=ticketRejected") })
        }
    }

    func testLateFileAfterCloseOrAccountInvalidationIsRejectedAndRemoved() async throws {
        for invalidate in [false, true] {
            let fixture = resource()
            let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
            let pause = BoundaryPause(); var events: [String] = []
            let qa = try ChatMediaBoundaryQA(mode: .holdFile, messageID: message, runID: UUID(), root: root,
                                            wait: { await pause.wait() }, record: { events.append($0) })
            let http = BoundaryHTTP(); let service = ChatMediaSignedDownloadService(repository: BoundaryRepository(expiry: fixture.mediaExpiresAt!), http: http)
            service.boundaryQA = qa
            let held = expectation(description: "성공 응답 파일 보류"); pause.next = held
            let destination = root.appendingPathComponent("destination")
            let task = Task { try await service.file(resource: fixture, maxBytes: 100, to: destination) }
            await fulfillment(of: [held], timeout: 2)
            XCTAssertEqual(http.calls, 1)
            XCTAssertTrue(http.files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
            if invalidate { service.invalidateSession() } else { task.cancel() }
            try Data(qa.runID.uuidString.utf8).write(to: qa.signal("file")); pause.resume()
            do { try await task.value; XCTFail("종료 작업에 늦은 원본 전달") } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertTrue(http.files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
            XCTAssertTrue(events.contains { $0.contains("event=fileRejected") })
            XCTAssertFalse(events.contains { $0.contains("event=fileDelivered") })
        }
    }

    func testTimeoutRemovesHeldFileAndDoesNotDeclareDelivery() async throws {
        let fixture = resource()
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        var clock = Date(); var events: [String] = []
        let qa = try ChatMediaBoundaryQA(mode: .holdFile, messageID: message, runID: UUID(), root: root,
                                        timeout: 1, now: { clock }, wait: { clock = clock.addingTimeInterval(2) }, record: { events.append($0) })
        let http = BoundaryHTTP(); let service = ChatMediaSignedDownloadService(repository: BoundaryRepository(expiry: fixture.mediaExpiresAt!), http: http)
        service.boundaryQA = qa
        let destination = root.appendingPathComponent("destination")
        do { try await service.file(resource: fixture, maxBytes: 100, to: destination); XCTFail("신호 없는 타임아웃 통과") }
        catch { XCTAssertTrue(error is ChatMediaBoundaryQA.Failure) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(http.files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertTrue(events.contains { $0.contains("event=timeout") })
    }

    func testExpiryControlDelaysOnlyFirstRequestAndRenewsOnce() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        var clock = Date(); var sleeps: [TimeInterval] = []; var events: [String] = []
        let resource = self.resource()
        let qa = try ChatMediaBoundaryQA(mode: .expiredOriginal, messageID: message, runID: UUID(), root: root,
            now: { clock }, sleep: { sleeps.append($0); clock = clock.addingTimeInterval($0) }, record: { events.append($0) })
        let repository = BoundaryRepository(expiry: resource.mediaExpiresAt!, now: { clock })
        let http = BoundaryHTTP(); http.expireFirst = true
        let service = ChatMediaSignedDownloadService(repository: repository, http: http, now: { clock })
        service.boundaryQA = qa
        let destination = root.appendingPathComponent("destination")
        try await service.file(resource: resource, maxBytes: 1000, to: destination)
        XCTAssertEqual(sleeps, [65])
        XCTAssertEqual(repository.calls, 2); XCTAssertEqual(http.calls, 2)
        XCTAssertEqual(try Data(contentsOf: destination), Data([1, 2, 3]))
        XCTAssertEqual(events.filter { $0.contains("event=renewing") }.count, 1)
        XCTAssertTrue(events.contains { $0.contains("status=400") && $0.contains("errorKind=expiredToken") })
        XCTAssertTrue(http.files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertFalse(events.contains { $0.contains("https://") || $0.contains(message) })
    }

    func testExpiryControlRejectsNormalOneHourURLWithoutWaiting() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        var didSleep = false
        let qa = try ChatMediaBoundaryQA(mode: .expiredOriginal, messageID: message, runID: UUID(), root: root,
                                        sleep: { _ in didSleep = true }, record: { _ in })
        let ticket = ChatMediaURLTicket(url: URL(string: "https://signed.invalid/media")!,
            urlExpiresAt: Date().addingTimeInterval(3600), mediaExpiresAt: resource().mediaExpiresAt!, generation: "123")
        do { try await qa.beforeDownload(resource(), ticket: ticket, attempt: 0); XCTFail("일반 1시간 URL을 기다리면 안 됨") }
        catch { XCTAssertTrue(error is ChatMediaBoundaryQA.Failure) }
        XCTAssertFalse(didSleep)
    }
}

@MainActor
private final class BoundaryPause {
    var next: XCTestExpectation?
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation = $0; next?.fulfill(); next = nil }
    }
    func resume() { let pending = continuation; continuation = nil; pending?.resume() }
}
@MainActor
private final class BoundaryRepository: ChatMediaURLRepository {
    let expiry: Date
    let now: () -> Date
    var calls = 0
    init(expiry: Date, now: @escaping () -> Date = Date.init) { self.expiry = expiry; self.now = now }
    static func ticket(expiry: Date) -> ChatMediaURLTicket {
        .init(url: URL(string: "https://signed.invalid/media")!, urlExpiresAt: Date().addingTimeInterval(60), mediaExpiresAt: expiry, generation: "123")
    }
    func issue(_ request: ChatMediaURLRequest) async throws -> ChatMediaURLTicket {
        calls += 1
        return .init(url: URL(string: "https://signed.invalid/media")!, urlExpiresAt: now().addingTimeInterval(60), mediaExpiresAt: expiry, generation: "123")
    }
}
private final class BoundaryHTTP: ChatMediaHTTPDownloading, @unchecked Sendable {
    @MainActor var calls = 0
    @MainActor var files: [URL] = []
    @MainActor var expireFirst = false
    func download(_ url: URL) async throws -> (URL, Int) {
        try await MainActor.run {
            calls += 1
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let expired = expireFirst && calls == 1
            let body = expired ? Data("<Error><Code>ExpiredToken</Code><Message>Invalid argument.</Message></Error>".utf8) : Data([1, 2, 3])
            try body.write(to: file); files.append(file)
            return (file, expired ? 400 : 200)
        }
    }
}
#endif
