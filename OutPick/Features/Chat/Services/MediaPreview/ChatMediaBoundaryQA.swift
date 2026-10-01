import Foundation

#if DEBUG
/// 지정 DEV 원본의 실제 응답 전달 시점만 제어한다. 제품의 취소·권한 검사는 우회하지 않는다.
@MainActor
final class ChatMediaBoundaryQA {
    enum Mode: String { case expiredOriginal, holdURL, holdFile }
    enum Failure: Error { case timedOut }
    static let roomID = "MFBgh49togDCjlnPt4CM"
    private static var processInstance: ChatMediaBoundaryQA?
    let mode: Mode
    let messageID: String
    let runID: UUID
    let directory: URL
    private let record: (String) -> Void
    private let wait: () async -> Void
    private let sleep: (TimeInterval) async throws -> Void
    private let now: () -> Date
    private let timeout: TimeInterval
    private var held = false
    private var delayedRequest = false

    init(mode: Mode, messageID: String, runID: UUID, root: URL,
         timeout: TimeInterval = 300, now: @escaping () -> Date = Date.init,
         sleep: @escaping (TimeInterval) async throws -> Void = {
             try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
         },
         wait: @escaping () async -> Void = {
             // 취소를 무시한 늦은 응답을 재현하되 별도 대기는 짧게 종료한다.
             _ = await Task.detached { try? await Task.sleep(nanoseconds: 200_000_000) }.value
         }, record: @escaping (String) -> Void = { print($0) }) throws {
        self.mode = mode; self.messageID = messageID; self.runID = runID
        self.directory = root.appendingPathComponent(runID.uuidString, isDirectory: true)
        self.timeout = timeout; self.now = now; self.wait = wait; self.sleep = sleep; self.record = record
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for stage in ["url", "file"] { try? FileManager.default.removeItem(at: signal(stage)) }
        event("configured")
    }

    static func configuration(info: [String: Any], env: [String: String]) -> (Mode, String, UUID)? {
        guard info["OUTPICK_ENVIRONMENT"] as? String == "development",
              info["OUTPICK_EXPECTED_FIREBASE_PROJECT_ID"] as? String == "outpick-test",
              env["OUTPICK_BOUNDARY_QA"] == "1",
              let mode = Mode(rawValue: env["OUTPICK_BOUNDARY_QA_MODE"] ?? ""),
              let message = env["OUTPICK_BOUNDARY_QA_MESSAGE"], UUID(uuidString: message) != nil,
              let run = UUID(uuidString: env["OUTPICK_BOUNDARY_QA_RUN"] ?? "") else { return nil }
        return (mode, message, run)
    }

    static func enabledForCurrentProcess() -> ChatMediaBoundaryQA? {
        guard let (mode, message, run) = configuration(info: Bundle.main.infoDictionary ?? [:],
                                                      env: ProcessInfo.processInfo.environment) else { return nil }
        if let existing = processInstance { return existing }
        guard let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let value = try? ChatMediaBoundaryQA(mode: mode, messageID: message, runID: run,
                                            root: root.appendingPathComponent("ChatBoundaryQA", isDirectory: true))
        processInstance = value
        return value
    }

    func matches(_ resource: ChatOriginalResource) -> Bool {
        guard resource.path.hasPrefix("gs://outpick-test-chat-media/"),
              let request = try? ChatMediaURLRequest(path: resource.path) else { return false }
        return matches(request)
    }
    func matches(_ request: ChatMediaURLRequest) -> Bool {
        request.roomID == Self.roomID && request.messageID == messageID && request.variant == "original"
    }
    func event(_ name: String, details: String = "") {
        record("[MediaBoundaryQA] run=\(runID.uuidString) mode=\(mode.rawValue) event=\(name) \(details) epoch=\(now().timeIntervalSince1970)")
    }
    func signal(_ stage: String) -> URL { directory.appendingPathComponent("release-\(stage)") }

    private func hold(_ stage: String) async throws {
        guard !held else { return }
        held = true
        event("holding", details: "stage=\(stage)")
        let deadline = now().addingTimeInterval(timeout)
        while now() < deadline {
            if let data = try? Data(contentsOf: signal(stage)),
               String(data: data, encoding: .utf8) == runID.uuidString {
                try FileManager.default.removeItem(at: signal(stage))
                event("released", details: "stage=\(stage) cancelled=\(Task.isCancelled)")
                return
            }
            await wait()
        }
        event("timeout", details: "stage=\(stage)")
        throw Failure.timedOut
    }

    func issued(_ request: ChatMediaURLRequest, ticket: ChatMediaURLTicket) async throws {
        guard matches(request) else { return }
        event("issued", details: "urlExpiresAt=\(ticket.urlExpiresAt.timeIntervalSince1970)")
        if mode == .holdURL { try await hold("url") }
    }
    func beforeDownload(_ resource: ChatOriginalResource, ticket: ChatMediaURLTicket, attempt: Int) async throws {
        guard matches(resource) else { return }
        if mode == .expiredOriginal, attempt == 0, !delayedRequest {
            delayedRequest = true
            event("waitingForExpiry", details: "urlExpiresAt=\(ticket.urlExpiresAt.timeIntervalSince1970)")
            let remaining = ticket.urlExpiresAt.addingTimeInterval(5).timeIntervalSince(now())
            guard remaining <= timeout else { event("invalidURLLifetime"); throw Failure.timedOut }
            if remaining > 0 { try await sleep(remaining) }
        }
        event("request", details: "attempt=\(attempt)")
    }
    func received(_ resource: ChatOriginalResource, file: URL, status: Int, attempt: Int) async throws {
        guard matches(resource) else { return }
        let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let kind = ChatMediaHTTPErrorKind.classify(status: status, file: file)
        event("response", details: "attempt=\(attempt) status=\(status) bytes=\(bytes) errorKind=\(kind.rawValue)")
        if mode == .holdFile, (200..<300).contains(status) { try await hold("file") }
    }
}
#endif
