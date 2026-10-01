import Foundation
import UIKit
import XCTest
@testable import OutPick

/// 실제 저장기의 분기와 파일 수명을 검사하되 사용자 권한·Photos 라이브러리는 변경하지 않는다.
@MainActor
final class PhotoLibrarySaverBoundaryTests: XCTestCase {
    func testAlreadyExpiredLeaseDoesNotRequestPermissionOrSubmit() async throws {
        let source = try makeSource(isVideo: false)
        defer { try? FileManager.default.removeItem(at: source) }
        let validity = PhotoSaveValidity()
        validity.invalidate()
        let probe = PhotoSaveProbe()
        let saver = makeSaver(probe: probe)
        let lease = makeLease(source, validity: validity)
        await expectCancellation { try await saver.saveOriginal(lease, isVideo: false) }
        let calls = await probe.snapshot()
        XCTAssertEqual(calls.permissions, 0)
        XCTAssertTrue(calls.submissions.isEmpty)
        await lease.release()
    }

    func testExpiryWhilePermissionIsPendingPreventsSubmission() async throws {
        try await verifyPermissionWait(cancel: false)
    }

    func testCancellationWhilePermissionIsPendingPreventsSubmission() async throws {
        try await verifyPermissionWait(cancel: true)
    }

    func testDeniedPermissionDoesNotPrepareOrSubmitOriginal() async throws {
        let source = try makeSource(isVideo: false)
        // 형식 준비를 먼저 했다면 저장 실패가 나도록 잘못된 합성 본문을 사용한다.
        try Data("not-an-image".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let probe = PhotoSaveProbe()
        let saver = makeSaver(probe: probe, granted: false)
        let lease = makeLease(source, validity: PhotoSaveValidity())
        do {
            try await saver.saveOriginal(lease, isVideo: false)
            XCTFail("권한 거절은 저장 성공으로 처리하면 안 된다")
        } catch {
            XCTAssertEqual(error as? PhotoLibrarySaveError, .permissionDenied)
        }
        let calls = await probe.snapshot()
        XCTAssertEqual(calls.permissions, 1)
        XCTAssertTrue(calls.submissions.isEmpty)
        XCTAssertTrue(lease.isValid)
        await lease.release()
    }

    func testSubmittedSaveSurvivesExpiryAndCancellationUntilSuccess() async throws {
        try await verifySubmittedSave(failure: false)
    }

    func testSubmittedFailurePropagatesAndCleansPreparedFile() async throws {
        try await verifySubmittedSave(failure: true)
    }

    private func verifyPermissionWait(cancel: Bool) async throws {
        for isVideo in [false, true] {
            let source = try makeSource(isVideo: isVideo)
            defer { try? FileManager.default.removeItem(at: source) }
            let validity = PhotoSaveValidity()
            let lease = makeLease(source, validity: validity)
            let probe = PhotoSaveProbe()
            let permission = PhotoPermissionWait()
            let started = expectation(description: "권한 응답 대기 시작")
            let saver = DefaultPhotoLibrarySaver(requestPermission: {
                await probe.recordPermission()
                return await permission.wait(started: started)
            }, submitOriginal: { prepared, video in
                await probe.recordSubmission(url: prepared.fileURL, isVideo: video)
            })
            let task = Task { try await saver.saveOriginal(lease, isVideo: isVideo) }
            await fulfillment(of: [started], timeout: 5)
            if cancel { task.cancel() }
            else { validity.invalidate() }
            await permission.finish(granted: true)
            await expectCancellation { try await task.value }
            let calls = await probe.snapshot()
            XCTAssertEqual(calls.permissions, 1)
            XCTAssertTrue(calls.submissions.isEmpty)
            await lease.release()
        }
    }

    private func verifySubmittedSave(failure: Bool) async throws {
        for isVideo in [false, true] {
            let source = try makeSource(isVideo: isVideo)
            defer { try? FileManager.default.removeItem(at: source) }
            let originalBytes = try Data(contentsOf: source)
            let validity = PhotoSaveValidity()
            let lease = makeLease(source, validity: validity)
            let probe = PhotoSaveProbe()
            let submission = PhotoSubmissionWait()
            let started = expectation(description: "Photos 제출 완료 응답 대기 시작")
            let saver = DefaultPhotoLibrarySaver(requestPermission: {
                await probe.recordPermission()
                return true
            }, submitOriginal: { prepared, video in
                await probe.recordSubmission(url: prepared.fileURL, isVideo: video)
                try await submission.wait(started: started)
            })
            let task = Task { try await saver.saveOriginal(lease, isVideo: isVideo) }
            await fulfillment(of: [started], timeout: 5)
            let calls = await probe.snapshot()
            XCTAssertEqual(calls.permissions, 1)
            XCTAssertEqual(calls.submissions.count, 1)
            let submitted = calls.submissions.first
            XCTAssertEqual(submitted?.isVideo, isVideo)
            if let submitted {
                if isVideo { XCTAssertEqual(submitted.url.pathExtension, "mp4") }
                else { XCTAssertTrue(["jpg", "jpeg"].contains(submitted.url.pathExtension)) }
                XCTAssertEqual(try Data(contentsOf: submitted.url), originalBytes)
            }
            validity.invalidate()
            task.cancel()
            XCTAssertTrue(lease.isValid)
            if let submitted { XCTAssertTrue(FileManager.default.fileExists(atPath: submitted.url.path)) }
            let callbackError = NSError(domain: "PhotoLibrarySaverBoundaryTests", code: 77)
            await submission.finish(result: failure ? .failure(callbackError) : .success(()))
            do {
                try await task.value
                if failure { XCTFail("Photos 완료 오류가 전달돼야 한다") }
            } catch {
                if failure {
                    XCTAssertEqual((error as NSError).domain, callbackError.domain)
                    XCTAssertEqual((error as NSError).code, callbackError.code)
                } else { XCTFail("제출 후 취소·만료는 완료 콜백 성공을 바꾸면 안 된다: \(error)") }
            }
            if let submitted { XCTAssertFalse(FileManager.default.fileExists(atPath: submitted.url.path)) }
            XCTAssertEqual(try Data(contentsOf: source), originalBytes)
            await lease.release()
            XCTAssertFalse(lease.isValid)
        }
    }

    private func makeSaver(probe: PhotoSaveProbe, granted: Bool = true) -> DefaultPhotoLibrarySaver {
        DefaultPhotoLibrarySaver(requestPermission: {
            await probe.recordPermission()
            return granted
        }, submitOriginal: { prepared, video in
            await probe.recordSubmission(url: prepared.fileURL, isVideo: video)
        })
    }

    private func makeLease(_ url: URL, validity: PhotoSaveValidity) -> ChatOriginalFileLease {
        ChatOriginalFileLease(fileURL: url, isValid: { validity.isValid }, release: {})
    }

    private func makeSource(isVideo: Bool) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoSaveBoundary-\(UUID()).bin")
        let data: Data
        if isVideo {
            // 타입 식별용 합성 헤더다. 실제 Photos 저장은 기존 정상 통합 테스트가 담당한다.
            data = Data([0, 0, 0, 20]) + Data("ftypmp42".utf8) + Data([0, 0, 0, 0]) + Data("mp42".utf8)
        } else {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
                UIColor.orange.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            }
            data = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        }
        try data.write(to: url)
        return url
    }

    private func expectCancellation(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("제출 전 만료·취소는 저장을 중단해야 한다")
        } catch is CancellationError {
        } catch { XCTFail("예상하지 않은 오류: \(error)") }
    }
}

private final class PhotoSaveValidity: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true
    var isValid: Bool { lock.withLock { valid } }
    func invalidate() { lock.withLock { valid = false } }
}

private actor PhotoSaveProbe {
    struct Submission: Sendable { let url: URL; let isVideo: Bool }
    private var permissions = 0
    private var submissions: [Submission] = []
    func recordPermission() { permissions += 1 }
    func recordSubmission(url: URL, isVideo: Bool) { submissions.append(Submission(url: url, isVideo: isVideo)) }
    func snapshot() -> (permissions: Int, submissions: [Submission]) { (permissions, submissions) }
}

private actor PhotoPermissionWait {
    private var result: Bool?
    private var continuation: CheckedContinuation<Bool, Never>?
    func wait(started: XCTestExpectation) async -> Bool {
        if let result { started.fulfill(); return result }
        return await withCheckedContinuation {
            continuation = $0
            started.fulfill()
        }
    }
    func finish(granted: Bool) {
        result = granted
        continuation?.resume(returning: granted)
        continuation = nil
    }
}

private actor PhotoSubmissionWait {
    private var result: Result<Void, Error>?
    private var continuation: CheckedContinuation<Void, Error>?
    func wait(started: XCTestExpectation) async throws {
        if let result { started.fulfill(); return try result.get() }
        try await withCheckedThrowingContinuation {
            continuation = $0
            started.fulfill()
        }
    }
    func finish(result: Result<Void, Error>) {
        self.result = result
        continuation?.resume(with: result)
        continuation = nil
    }
}
