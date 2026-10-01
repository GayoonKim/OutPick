#if DEBUG
import Foundation

struct ChatSignedURLQAResponse: Sendable {
    let status: Int
    let bytes: Int
    let rangeStart: Int?
    let rangeEnd: Int?
    let rangeTotal: Int?
    var errorKind: ChatMediaHTTPErrorKind = .other
    var expiredError: Bool { errorKind.isExpiry(status: status) }
}

struct ChatSignedURLQARecord {
    let event: String
    var response: ChatSignedURLQAResponse? = nil
    var expiresAt: Date? = nil
    let passed: Bool
}

protocol ChatSignedURLQAHTTP: Sendable {
    func get(_ url: URL, range: Bool) async throws -> ChatSignedURLQAResponse
}

struct ChatSignedURLQAHTTPClient: ChatSignedURLQAHTTP {
    private let download: @Sendable (URLSession, URLRequest) async throws -> (URL, URLResponse)

    init(download: @escaping @Sendable (URLSession, URLRequest) async throws -> (URL, URLResponse) = {
        try await $0.download(for: $1)
    }) {
        self.download = download
    }

    func get(_ url: URL, range: Bool) async throws -> ChatSignedURLQAResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 60
        if range { request.setValue("bytes=0-15", forHTTPHeaderField: "Range") }
        let (file, response) = try await download(session, request)
        defer { try? FileManager.default.removeItem(at: file) }
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let bytes = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let bounds = Self.bounds(response.value(forHTTPHeaderField: "Content-Range"))
        return ChatSignedURLQAResponse(status: response.statusCode, bytes: bytes,
            rangeStart: bounds?.0, rangeEnd: bounds?.1, rangeTotal: bounds?.2,
            errorKind: ChatMediaHTTPErrorKind.classify(status: response.statusCode, file: file))
    }

    static func bounds(_ header: String?) -> (Int, Int, Int)? {
        guard let header, header.hasPrefix("bytes ") else { return nil }
        let values = header.dropFirst(6).split(separator: "/")
        guard values.count == 2, let total = Int(values[1]) else { return nil }
        let ends = values[0].split(separator: "-", omittingEmptySubsequences: false)
        guard ends.count == 2, let start = Int(ends[0]), let end = Int(ends[1]),
              start >= 0, end >= start, total > end else { return nil }
        return (start, end, total)
    }
}

/// 지정한 개발 QA 메시지 한 개만 관측한다. 서명 URL은 실행 중 메모리 밖으로 나가지 않는다.
@MainActor
final class ChatSignedURLHTTPQA {
    private let messageID: String
    private let http: any ChatSignedURLQAHTTP
    private let now: () -> Date
    private let sleep: (TimeInterval) async throws -> Void
    private let record: (ChatSignedURLQARecord) -> Void
    private var task: Task<Void, Never>?
    private var started = false
    private var valid = true
    private var targetPath: String?

    init(messageID: String, http: any ChatSignedURLQAHTTP = ChatSignedURLQAHTTPClient(),
         now: @escaping () -> Date = Date.init,
         sleep: @escaping (TimeInterval) async throws -> Void = {
             try await Task.sleep(nanoseconds: UInt64(max(0, $0) * 1_000_000_000))
         }, record: @escaping (ChatSignedURLQARecord) -> Void) {
        self.messageID = messageID; self.http = http; self.now = now
        self.sleep = sleep; self.record = record
    }

    static func enabledForCurrentProcess(
        info: [String: Any] = Bundle.main.infoDictionary ?? [:],
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> ChatSignedURLHTTPQA? {
        guard info["OUTPICK_ENVIRONMENT"] as? String == "development",
              info["OUTPICK_EXPECTED_FIREBASE_PROJECT_ID"] as? String == "outpick-test",
              env["OUTPICK_SIGNED_HTTP_QA"] == "1",
              let message = env["OUTPICK_SIGNED_HTTP_QA_MESSAGE"], !message.isEmpty else { return nil }
        let run = UUID().uuidString
        return ChatSignedURLHTTPQA(messageID: message) { entry in
            let response = entry.response
            print("[SignedHTTPQA] run=\(run) event=\(entry.event) status=\(response?.status ?? 0) bytes=\(response?.bytes ?? 0) rangeStart=\(response?.rangeStart ?? -1) rangeEnd=\(response?.rangeEnd ?? -1) rangeTotal=\(response?.rangeTotal ?? -1) expiredError=\(response?.expiredError ?? false) errorKind=\(response?.errorKind.rawValue ?? "other") expiresAt=\(entry.expiresAt?.timeIntervalSince1970 ?? 0) passed=\(entry.passed) epoch=\(Date().timeIntervalSince1970)")
        }
    }

    func observe(resource: ChatOriginalResource, ticket: ChatMediaURLTicket) {
        guard valid, let request = try? ChatMediaURLRequest(path: resource.path),
              request.roomID == "MFBgh49togDCjlnPt4CM", request.messageID == messageID,
              request.variant == "original" else { return }
        record(.init(event: "ticketObserved", expiresAt: ticket.urlExpiresAt, passed: true))
        guard !started else { return }
        started = true; targetPath = resource.path
        let http = self.http, now = self.now, sleep = self.sleep, record = self.record
        task = Task {
            do {
                try Task.checkCancellation()
                let full = try await http.get(ticket.url, range: false)
                try Task.checkCancellation()
                let fullPassed = full.status == 200 && full.bytes >= 16 && now() < ticket.urlExpiresAt
                record(.init(event: "get", response: full, passed: fullPassed))
                let range = try await http.get(ticket.url, range: true)
                try Task.checkCancellation()
                let rangePassed = range.status == 206 && range.bytes == 16 && range.rangeStart == 0
                    && range.rangeEnd == 15 && range.rangeTotal == full.bytes && now() < ticket.urlExpiresAt
                record(.init(event: "range", response: range, passed: rangePassed))
                guard fullPassed && rangePassed else { record(.init(event: "incomplete", passed: false)); return }
                record(.init(event: "waitingForExpiry", expiresAt: ticket.urlExpiresAt, passed: true))
                while now() < ticket.urlExpiresAt.addingTimeInterval(5) {
                    try await sleep(ticket.urlExpiresAt.addingTimeInterval(5).timeIntervalSince(now()))
                    try Task.checkCancellation()
                }
                let expired = try await http.get(ticket.url, range: true)
                try Task.checkCancellation()
                let passed = expired.expiredError
                record(.init(event: "expired", response: expired, passed: passed))
                record(.init(event: "complete", passed: passed))
            } catch {
                record(.init(event: Task.isCancelled || error is CancellationError ? "cancelled" : "incomplete", passed: false))
            }
        }
    }

    func remove(path: String) { if path == targetPath { invalidate() } }
    func invalidate() { valid = false; task?.cancel(); task = nil }
    deinit { task?.cancel() }
}
#endif
