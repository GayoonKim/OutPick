//
//  LookbookTestAdminServerClient.swift
//  OutPickUITests
//
//  Created by Codex on 5/20/26.
//

import Foundation
import XCTest

enum LookbookTestAdminSeedRoute: String {
    case basic = "lookbook-basic"
    case comments = "lookbook-comments"
}

struct LookbookTestAdminServerClient {
    private let baseURL: URL
    private let timeout: TimeInterval

    init(
        baseURL: URL = LookbookTestAdminServerClient.defaultBaseURL(),
        timeout: TimeInterval = 10
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
    }

    func assertHealthy() throws {
        let response: HealthResponse = try request(
            path: "/health",
            method: "GET",
            body: nil
        )

        XCTAssertEqual(response.status, "ok")
        XCTAssertEqual(response.firebaseProjectID, "outpick-test")
        XCTAssertEqual(response.serviceAccountProjectID, "outpick-test")
        XCTAssertTrue(response.firebaseAdminInitialized)
    }

    @discardableResult
    func reset(testRunId: String? = nil, dryRun: Bool = false) throws -> ResetResponse {
        try request(
            path: "/reset",
            method: "POST",
            body: ResetRequest(testRunId: testRunId, dryRun: dryRun)
        )
    }

    @discardableResult
    func seed(_ route: LookbookTestAdminSeedRoute, testRunId: String? = nil) throws -> SeedResponse {
        try request(
            path: "/seed/\(route.rawValue)",
            method: "POST",
            body: SeedRequest(testRunId: testRunId)
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) throws -> Response {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let result = perform(request)

        if let error = result.error {
            throw XCTSkip("Test Admin Server 요청 실패: \(error.localizedDescription). 서버 실행 상태를 확인해야 합니다.")
        }

        guard let response = result.response as? HTTPURLResponse else {
            throw XCTSkip("Test Admin Server 응답을 확인할 수 없습니다.")
        }

        guard (200..<300).contains(response.statusCode) else {
            let message = result.data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            XCTFail("Test Admin Server 응답 실패: status=\(response.statusCode), body=\(message)")
            throw TestAdminServerClientError.invalidStatusCode(response.statusCode)
        }

        guard let data = result.data else {
            throw TestAdminServerClientError.emptyResponse
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        body: Never?
    ) throws -> Response {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout

        let result = perform(request)

        if let error = result.error {
            throw XCTSkip("Test Admin Server 요청 실패: \(error.localizedDescription). 서버 실행 상태를 확인해야 합니다.")
        }

        guard let response = result.response as? HTTPURLResponse else {
            throw XCTSkip("Test Admin Server 응답을 확인할 수 없습니다.")
        }

        guard (200..<300).contains(response.statusCode) else {
            let message = result.data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            XCTFail("Test Admin Server 응답 실패: status=\(response.statusCode), body=\(message)")
            throw TestAdminServerClientError.invalidStatusCode(response.statusCode)
        }

        guard let data = result.data else {
            throw TestAdminServerClientError.emptyResponse
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func perform(_ request: URLRequest) -> RequestResult {
        let semaphore = DispatchSemaphore(value: 0)
        var requestResult = RequestResult(data: nil, response: nil, error: nil)

        URLSession.shared.dataTask(with: request) { data, response, error in
            requestResult = RequestResult(data: data, response: response, error: error)
            semaphore.signal()
        }.resume()

        let waitResult = semaphore.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            return RequestResult(
                data: nil,
                response: nil,
                error: TestAdminServerClientError.timeout
            )
        }

        return requestResult
    }

    private static func defaultBaseURL() -> URL {
        if let rawValue = ProcessInfo.processInfo.environment["OUTPICK_TEST_ADMIN_SERVER_URL"],
           let url = URL(string: rawValue),
           rawValue.isEmpty == false {
            return url
        }

        return URL(string: "http://127.0.0.1:45731")!
    }
}

private struct RequestResult {
    let data: Data?
    let response: URLResponse?
    let error: Error?
}

private enum TestAdminServerClientError: Error {
    case timeout
    case emptyResponse
    case invalidStatusCode(Int)
}

private struct HealthResponse: Decodable {
    let status: String
    let firebaseProjectID: String
    let serviceAccountProjectID: String
    let firebaseAdminInitialized: Bool
}

struct ResetResponse: Decodable {
    let status: String
    let dryRun: Bool
    let matchedDocumentPaths: [String]
    let deletedDocumentCount: Int
    let matchedAuthUserIDs: [String]
    let deletedAuthUserCount: Int
}

struct SeedResponse: Decodable {
    let status: String
    let brandID: String
    let seasonID: String
    let postID: String
    let testRunId: String?
}

private struct ResetRequest: Encodable {
    let testRunId: String?
    let dryRun: Bool
}

private struct SeedRequest: Encodable {
    let testRunId: String?
}
