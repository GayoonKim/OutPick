import Foundation
import XCTest
@testable import OutPick

@MainActor
final class ChatMediaSignedDownloadTests: XCTestCase {
    func testTicketRejectsExtendedExpiryAndDeletedResource() async throws {
        let now = Date()
        let resource = resource(expiry: now.addingTimeInterval(7200))
        let repository = MediaURLSpy(now: { now }, expiry: resource.mediaExpiresAt!)
        repository.ttl = 3601
        let service = ChatMediaSignedDownloadService(repository: repository, now: { now })
        do { _ = try await service.ticket(for: resource); XCTFail("1시간 상한 초과 허용") }
        catch { XCTAssertEqual(error as? ChatVideoPlaybackError, .invalidResponse) }
        repository.ttl = 60
        let altered = ChatOriginalResource(path: resource.path, version: "123", mediaExpiresAt: now.addingTimeInterval(7100))
        do { _ = try await service.ticket(for: altered); XCTFail("미디어 기한 불일치 허용") }
        catch { XCTAssertEqual(error as? ChatVideoPlaybackError, .invalidResponse) }
        _ = try await service.ticket(for: resource)
        let calls = repository.calls
        service.remove(path: resource.path)
        do { _ = try await service.ticket(for: resource); XCTFail("삭제된 리소스 재발급") }
        catch { XCTAssertEqual(error as? ChatVideoPlaybackError, .unavailable) }
        XCTAssertEqual(repository.calls, calls)
    }

    func testInvalidatedSessionDiscardsInFlightHTTPFile() async throws {
        let now = Date()
        let resource = resource(expiry: now.addingTimeInterval(600))
        let repository = MediaURLSpy(now: { now }, expiry: resource.mediaExpiresAt!)
        let http = MediaHTTPSpy()
        let service = ChatMediaSignedDownloadService(repository: repository, http: http, now: { now })
        http.onDownload = { _ in service.invalidateSession(); return 200 }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { try await service.file(resource: resource, maxBytes: 100, to: destination); XCTFail("종료된 세션에 파일 반환") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(http.files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    private func resource(expiry: Date) -> ChatOriginalResource {
        ChatOriginalResource(path: "gs://ready/rooms/room/messages/message/attachments/attachment/display",
            version: "123", mediaExpiresAt: expiry)
    }

    func testRequestUsesOnlyIdentifiersAndVariant() async throws {
        let now = Date()
        let transport = MediaURLTransport(response: ["url": "https://signed.invalid/media", "generation": "123",
            "urlExpiresAt": now.addingTimeInterval(60).timeIntervalSince1970,
            "mediaExpiresAt": now.addingTimeInterval(600).timeIntervalSince1970])
        let request = try ChatMediaURLRequest(path: "gs://ready/rooms/room/messages/message/attachments/attachment/thumbnail")
        _ = try await CloudFunctionsChatMediaURLRepository(transport: transport).issue(request)
        XCTAssertEqual(transport.name, "issueChatMediaURL")
        XCTAssertEqual(transport.data as? [String: String], ["roomID": "room", "messageID": "message", "attachmentID": "attachment", "variant": "thumbnail"])
        XCTAssertThrowsError(try ChatMediaURLRequest(path: "https://arbitrary.invalid/image"))
    }

    func testConcurrentRequestsShareTicketAndAccountInvalidationRejectsLateResponse() async throws {
        let now = Date()
        let resource = resource(expiry: now.addingTimeInterval(600))
        let repository = MediaURLSpy(now: { now }, expiry: resource.mediaExpiresAt!)
        repository.delayed = true
        let service = ChatMediaSignedDownloadService(repository: repository, now: { now })
        let first = Task { try await service.ticket(for: resource) }
        let second = Task { try await service.ticket(for: resource) }
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(repository.calls, 1)
        service.invalidateSession()
        repository.finish()
        for task in [first, second] {
            do { _ = try await task.value; XCTFail("종료된 세션에 늦은 URL 반환") }
            catch { XCTAssertTrue(error is CancellationError) }
        }
    }

    func testCachedTicketIsReusedAndGenerationMismatchIsRejected() async throws {
        let now = Date()
        let resource = resource(expiry: now.addingTimeInterval(600))
        let repository = MediaURLSpy(now: { now }, expiry: resource.mediaExpiresAt!)
        let service = ChatMediaSignedDownloadService(repository: repository, now: { now })
        _ = try await service.ticket(for: resource)
        _ = try await service.ticket(for: resource)
        XCTAssertEqual(repository.calls, 1)
        let wrong = ChatOriginalResource(path: resource.path, version: "456", mediaExpiresAt: resource.mediaExpiresAt)
        do { _ = try await service.ticket(for: wrong); XCTFail("다른 generation 허용") }
        catch { XCTAssertEqual(error as? ChatVideoPlaybackError, .invalidResponse) }
    }

    func testExpiredURLDownloadRenewsOnceAndPreservesResourceExpiry() async throws {
        for status in [400, 403] {
            var now = Date()
            let resource = resource(expiry: now.addingTimeInterval(600))
            let repository = MediaURLSpy(now: { now }, expiry: resource.mediaExpiresAt!)
            repository.ttl = 1
            let http = MediaHTTPSpy()
            http.body = { count in count == 1 ? Data((status == 400
                ? "<Error><Code>ExpiredToken</Code><Message>Invalid argument.</Message></Error>"
                : "<Error><Code>AccessDenied</Code><Message>Request has expired.</Message></Error>").utf8) : Data([1, 2, 3]) }
            http.onDownload = { count in now = now.addingTimeInterval(2); return count == 1 ? status : 200 }
            let service = ChatMediaSignedDownloadService(repository: repository, http: http, now: { now })
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: destination) }
            try await service.file(resource: resource, maxBytes: 100, to: destination)
            XCTAssertEqual(repository.calls, 2); XCTAssertEqual(http.calls, 2)
            XCTAssertEqual(try Data(contentsOf: destination), Data([1, 2, 3]))
            XCTAssertEqual(repository.expiry, resource.mediaExpiresAt)
            XCTAssertTrue(http.files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        }
    }

    func testNonExpiryErrorsDoNotRenewEvenAfterURLDeadline() async throws {
        for (status, body) in [
            (400, "<Error><Code>InvalidArgument</Code><Message>Request has expired.</Message></Error>"),
            (403, "<Error><Code>AccessDenied</Code><Message>Access denied.</Message></Error>"),
            (400, "<Error><Code>ExpiredToken</Code>"),
            (500, "<Error><Code>ExpiredToken</Code></Error>")
        ] {
            var now = Date()
            let resource = resource(expiry: now.addingTimeInterval(600))
            let repository = MediaURLSpy(now: { now }, expiry: resource.mediaExpiresAt!)
            repository.ttl = 1
            let http = MediaHTTPSpy()
            http.body = { _ in Data(body.utf8) }
            http.onDownload = { _ in now = now.addingTimeInterval(2); return status }
            let service = ChatMediaSignedDownloadService(repository: repository, http: http, now: { now })
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do { try await service.file(resource: resource, maxBytes: 100, to: destination); XCTFail("만료 외 오류 허용") }
            catch { XCTAssertEqual(error as? ChatVideoPlaybackError, .temporarilyUnavailable) }
            XCTAssertEqual(repository.calls, 1); XCTAssertEqual(http.calls, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertTrue(http.files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        }
    }

    func testExpiredTokenDoesNotRenewBeforeLocalURLDeadline() async throws {
        let now = Date()
        let resource = resource(expiry: now.addingTimeInterval(600))
        let repository = MediaURLSpy(now: { now }, expiry: resource.mediaExpiresAt!)
        let http = MediaHTTPSpy()
        http.body = { _ in Data("<Error><Code>ExpiredToken</Code></Error>".utf8) }
        http.onDownload = { _ in 400 }
        let service = ChatMediaSignedDownloadService(repository: repository, http: http, now: { now })
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { try await service.file(resource: resource, maxBytes: 100, to: destination); XCTFail("기한 전 재발급 허용") }
        catch { XCTAssertEqual(error as? ChatVideoPlaybackError, .temporarilyUnavailable) }
        XCTAssertEqual(repository.calls, 1); XCTAssertEqual(http.calls, 1)
        XCTAssertTrue(http.files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    func testPermissionFailureDoesNotRenewAndExpiryDuringDownloadDiscardsFile() async throws {
        var now = Date()
        let resource = resource(expiry: now.addingTimeInterval(600))
        let repository = MediaURLSpy(now: { now }, expiry: resource.mediaExpiresAt!)
        let http = MediaHTTPSpy()
        http.onDownload = { _ in 403 }
        let service = ChatMediaSignedDownloadService(repository: repository, http: http, now: { now })
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { try await service.file(resource: resource, maxBytes: 100, to: destination); XCTFail("권한 실패 허용") }
        catch { XCTAssertEqual(error as? ChatVideoPlaybackError, .temporarilyUnavailable) }
        XCTAssertEqual(repository.calls, 1); XCTAssertEqual(http.calls, 1)
        http.onDownload = { _ in now = resource.mediaExpiresAt!; return 200 }
        do { try await service.file(resource: resource, maxBytes: 100, to: destination); XCTFail("만료 파일 반환") }
        catch { XCTAssertEqual(error as? ChatVideoPlaybackError, .expired) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(http.files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    func testSecondExpiredURLFailureStopsAtTwoDownloads() async throws {
        var now = Date()
        let resource = resource(expiry: now.addingTimeInterval(600))
        let repository = MediaURLSpy(now: { now }, expiry: resource.mediaExpiresAt!)
        repository.ttl = 1
        let http = MediaHTTPSpy()
        http.body = { _ in Data("<Error><Code>ExpiredToken</Code></Error>".utf8) }
        http.onDownload = { _ in now = now.addingTimeInterval(2); return 400 }
        let service = ChatMediaSignedDownloadService(repository: repository, http: http, now: { now })
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { try await service.file(resource: resource, maxBytes: 100, to: destination); XCTFail("두 번째 실패 허용") }
        catch { XCTAssertEqual(error as? ChatVideoPlaybackError, .temporarilyUnavailable) }
        XCTAssertEqual(repository.calls, 2); XCTAssertEqual(http.calls, 2)
        XCTAssertTrue(http.files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }
}

@MainActor
private final class MediaURLSpy: ChatMediaURLRepository {
    let now: () -> Date
    let expiry: Date
    var ttl: TimeInterval = 60
    var calls = 0
    var delayed = false
    var continuation: CheckedContinuation<Void, Never>?
    init(now: @escaping () -> Date, expiry: Date) { self.now = now; self.expiry = expiry }
    func issue(_ request: ChatMediaURLRequest) async throws -> ChatMediaURLTicket {
        calls += 1
        if delayed { await withCheckedContinuation { continuation = $0 } }
        return ChatMediaURLTicket(url: URL(string: "https://signed.invalid/media")!,
            urlExpiresAt: now().addingTimeInterval(ttl), mediaExpiresAt: expiry, generation: "123")
    }
    func finish() { let pending = continuation; continuation = nil; pending?.resume() }
}

private final class MediaHTTPSpy: ChatMediaHTTPDownloading, @unchecked Sendable {
    @MainActor var calls = 0
    @MainActor var files: [URL] = []
    @MainActor var onDownload: (Int) -> Int = { _ in 200 }
    @MainActor var body: (Int) -> Data = { _ in Data([1, 2, 3]) }
    func download(_ url: URL) async throws -> (URL, Int) {
        try await MainActor.run {
            calls += 1
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try body(calls).write(to: file); files.append(file)
            return (file, onDownload(calls))
        }
    }
}

private final class MediaURLTransport: CloudFunctionsTransporting {
    let response: [String: Any]
    var name: String?
    var data: [String: Any] = [:]
    init(response: [String: Any]) { self.response = response }
    func call(_ name: String, data: [String: Any]) async throws -> [String: Any] {
        self.name = name; self.data = data; return response
    }
}
