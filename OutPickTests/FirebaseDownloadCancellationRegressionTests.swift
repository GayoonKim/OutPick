import XCTest
import FirebaseCore
@testable import FirebaseStorage
import GTMSessionFetcherCore
@testable import OutPick

/// SDK의 취소 상태 보호를 실제 SDK 코드로 검증한다. 인증·HTTP는 격리한 fake 서비스로 대체한다.
@MainActor
final class FirebaseDownloadCancellationRegressionTests: XCTestCase {
    func testCancelledDownloadCannotRestartWhenEnqueuedAfterCancellation() async throws {
        let name = "CancellationRegression-\(UUID().uuidString)"
        // 앱 호스트의 유효한 Firebase 설정을 사용하되 bucket/전송 서비스는 별도로 격리한다.
        let app = try XCTUnwrap(FirebaseApp.app())
        let storage = Storage.storage(app: app, url: "gs://\(name.lowercased()).invalid")
        let service = await StorageFetcherService.shared.service(storage)
        // 이 테스트 전용 bucket의 서비스만 설정하며 앱의 Firebase 인증/네트워크는 변경하지 않는다.
        service.authorizer = nil
        service.isRetryEnabled = false
        let restarted = expectation(description: "취소된 SDK 작업이 전송을 재시작하면 안 됨")
        restarted.isInverted = true
        let controlFetched = expectation(description: "정상 전송으로 fake 경계 유효성 확인")
        service.testBlock = { fetcher, response in
            let url = fetcher.request!.url!
            if url.path.contains("cancelled") { restarted.fulfill() }
            else { controlFetched.fulfill() }
            response(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil), Data([1, 2, 3]), nil)
        }
        defer { service.testBlock = nil }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cancelledURL = root.appendingPathComponent("cancelled")
        let task = StorageDownloadTask(reference: storage.reference(withPath: "cancelled"), queue: DispatchQueue(label: name), file: cancelledURL)
        let cancelled = expectation(description: "SDK 취소 완료")
        task.observe(.failure) { _ in cancelled.fulfill() }
        task.cancel()
        await fulfillment(of: [cancelled], timeout: 3)
        // SDK 준비 Task가 늦게 실행되는 순서를 직접 재현한다.
        task.enqueue()
        try await FirebaseImageDownload.file(from: storage.reference(withPath: "control"), to: root.appendingPathComponent("control"), maxBytes: 100)
        await fulfillment(of: [controlFetched, restarted], timeout: 0.5)
        XCTAssertEqual(task.state, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelledURL.path))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("control")), Data([1, 2, 3]))
    }
}
