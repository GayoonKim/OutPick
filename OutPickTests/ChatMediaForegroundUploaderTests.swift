import XCTest
@testable import OutPick

final class ChatMediaForegroundUploaderTests: XCTestCase {
    func testAlreadyCanceledUploadFinishesWithoutWaitingForDelegate() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UploadSuccessProtocol.self]
        let uploader = URLSessionChatMediaForegroundUploader(configuration: configuration)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let completed = expectation(description: "등록 전 취소 완료")
        Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            let source = ChatMediaSourceDescriptor(index: 0, fileURL: file, contentType: "image/jpeg",
                sizeBytes: 1, sha256: "", mediaFormat: "jpeg", isAnimated: false)
            let target = ChatMediaUploadTarget(attachmentID: "a", sourceIndex: 0, path: "p",
                signedURL: URL(string: "https://upload.invalid/canceled")!, requiredHeaders: [:],
                contentType: "image/jpeg", sizeBytes: 1, sha256: "")
            do {
                _ = try await uploader.upload(source: source, target: target, onProgress: { _ in })
                XCTFail("취소된 업로드가 성공하면 안 됩니다")
            } catch { XCTAssertTrue(error is CancellationError) }
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 10)
    }

    func testConcurrentFirstUploadsAllComplete() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UploadSuccessProtocol.self]
        let uploader = URLSessionChatMediaForegroundUploader(configuration: configuration)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let completed = expectation(description: "모든 동시 업로드 완료")
        completed.expectedFulfillmentCount = 30
        for index in 0..<30 {
            Task.detached {
                let source = ChatMediaSourceDescriptor(index: index, fileURL: file,
                    contentType: "image/jpeg", sizeBytes: 1, sha256: "", mediaFormat: "jpeg", isAnimated: false)
                let target = ChatMediaUploadTarget(attachmentID: "a\(index)", sourceIndex: index,
                    path: "p\(index)", signedURL: URL(string: "https://upload.invalid/\(index)")!,
                    requiredHeaders: [:], contentType: "image/jpeg", sizeBytes: 1, sha256: "")
                do {
                    let result = try await uploader.upload(source: source, target: target, onProgress: { _ in })
                    XCTAssertEqual(result.sourceIndex, index)
                } catch { XCTFail("업로드 실패: \(error)") }
                completed.fulfill()
            }
        }
        await fulfillment(of: [completed], timeout: 10)
    }
}

private final class UploadSuccessProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
