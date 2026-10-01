import Foundation
import FirebaseFunctions

struct ChatMediaURLRequest: Hashable, Sendable {
    let roomID: String
    let messageID: String
    let attachmentID: String
    let variant: String

    init(path: String) throws {
        let value: String
        if path.hasPrefix("gs://"), let url = URL(string: path), url.host != nil {
            value = String(url.path.dropFirst())
        } else { value = path }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 7, parts[0] == "rooms", parts[2] == "messages", parts[4] == "attachments",
              !parts[1].isEmpty, !parts[3].isEmpty, !parts[5].isEmpty,
              ["display", "thumbnail"].contains(parts[6]) else { throw ChatVideoPlaybackError.invalidResponse }
        roomID = parts[1]; messageID = parts[3]; attachmentID = parts[5]
        variant = parts[6] == "display" ? "original" : "thumbnail"
    }
}

struct ChatMediaURLTicket: Sendable {
    let url: URL
    let urlExpiresAt: Date
    let mediaExpiresAt: Date
    let generation: String
}

protocol ChatMediaURLRepository {
    func issue(_ request: ChatMediaURLRequest) async throws -> ChatMediaURLTicket
}

final class CloudFunctionsChatMediaURLRepository: ChatMediaURLRepository {
    private let transport: any CloudFunctionsTransporting
    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) { self.transport = transport }

    func issue(_ request: ChatMediaURLRequest) async throws -> ChatMediaURLTicket {
        do {
            let response = try await transport.call("issueChatMediaURL", data: [
                "roomID": request.roomID, "messageID": request.messageID,
                "attachmentID": request.attachmentID, "variant": request.variant
            ])
            let decoder = CloudFunctionResponseDecoder(dictionary: response)
            let generation = try decoder.string("generation")
            guard let url = URL(string: try decoder.string("url")), url.scheme == "https", url.host != nil,
                  let expires = decoder.optionalDate("urlExpiresAt"), let mediaExpires = decoder.optionalDate("mediaExpiresAt"),
                  expires <= mediaExpires, !generation.isEmpty, generation.allSatisfy(\.isNumber) else {
                throw ChatVideoPlaybackError.invalidResponse
            }
            return ChatMediaURLTicket(url: url, urlExpiresAt: expires, mediaExpiresAt: mediaExpires, generation: generation)
        } catch let error as ChatVideoPlaybackError { throw error }
        catch {
            let failure = error as NSError
            let details = failure.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
            if details?["errorCode"] as? String == "MEDIA_EXPIRED" { throw ChatVideoPlaybackError.expired }
            if failure.domain == FunctionsErrorDomain {
                switch FunctionsErrorCode(rawValue: failure.code) {
                case .permissionDenied, .unauthenticated: throw ChatVideoPlaybackError.permissionDenied
                case .notFound: throw ChatVideoPlaybackError.unavailable
                default: break
                }
            }
            // SDK 오류에 포함될 수 있는 서명 URL을 외부로 전달하지 않는다.
            throw ChatVideoPlaybackError.temporarilyUnavailable
        }
    }
}

protocol ChatMediaHTTPDownloading: Sendable {
    func download(_ url: URL) async throws -> (URL, Int)
}

/// 서버 본문은 보관하지 않고 허용된 만료 오류만 고정된 값으로 분류한다.
enum ChatMediaHTTPErrorKind: String, Sendable {
    case expiredToken, expiredRequest, other

    func isExpiry(status: Int) -> Bool {
        switch self {
        case .expiredToken: return status == 400
        case .expiredRequest: return status == 403
        case .other: return false
        }
    }

    static func classify(status: Int, file: URL) -> Self {
        guard status == 400 || status == 403,
              let handle = try? FileHandle(forReadingFrom: file) else { return .other }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 65537), !data.isEmpty, data.count <= 65536,
              let text = String(data: data, encoding: .utf8),
              !text.uppercased().contains("<!DOCTYPE"), !text.uppercased().contains("<!ENTITY") else { return .other }
        let delegate = ChatMediaHTTPErrorXML()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.isValid else { return .other }
        if status == 400, delegate.code == "ExpiredToken" { return .expiredToken }
        if status == 403, delegate.code == "AccessDenied",
           ["request has expired", "request has expired."].contains(delegate.message.lowercased()) {
            return .expiredRequest
        }
        return .other
    }
}

private final class ChatMediaHTTPErrorXML: NSObject, XMLParserDelegate {
    private var path: [String] = []
    private var codeCount = 0
    private var messageCount = 0
    private var valid = true
    private(set) var code = ""
    private(set) var message = ""
    var isValid: Bool { valid && path.isEmpty && codeCount == 1 && !code.isEmpty }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        path.append(elementName)
        if path.count == 1 && elementName != "Error" { valid = false; parser.abortParsing() }
        if path == ["Error", "Code"] { codeCount += 1 }
        if path == ["Error", "Message"] { messageCount += 1 }
        if codeCount > 1 || messageCount > 1 ||
            (path.count > 2 && ["Code", "Message"].contains(path[1])) {
            valid = false; parser.abortParsing()
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if path == ["Error", "Code"] { code += string }
        if path == ["Error", "Message"] { message += string }
        if code.count > 256 || message.count > 256 { valid = false; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if path == ["Error", "Code"] { code = code.trimmingCharacters(in: .whitespacesAndNewlines) }
        if path == ["Error", "Message"] { message = message.trimmingCharacters(in: .whitespacesAndNewlines) }
        path.removeLast()
    }
}

struct ChatMediaHTTPDownloader: ChatMediaHTTPDownloading {
    func download(_ url: URL) async throws -> (URL, Int) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (file, response) = try await session.download(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
            return (file, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch is CancellationError { throw CancellationError() }
        catch { throw ChatVideoPlaybackError.temporarilyUnavailable }
    }
}

/// URL은 이 계정의 Container 메모리에만 보관한다.
@MainActor
final class ChatMediaSignedDownloadService {
#if DEBUG
    var httpQA: ChatSignedURLHTTPQA?
    var boundaryQA: ChatMediaBoundaryQA?
#endif
    private let repository: any ChatMediaURLRepository
    private let http: any ChatMediaHTTPDownloading
    private let now: () -> Date
    private var tickets: [ChatMediaURLRequest: ChatMediaURLTicket] = [:]
    private var flights: [ChatMediaURLRequest: (UUID, Task<ChatMediaURLTicket, Error>)] = [:]
    private var resources: [String: ChatOriginalResource] = [:]
    private var removedPaths = Set<String>()
    private var expiryTimer: Timer?
    private var valid = true

    init(repository: any ChatMediaURLRepository = CloudFunctionsChatMediaURLRepository(),
         http: any ChatMediaHTTPDownloading = ChatMediaHTTPDownloader(), now: @escaping () -> Date = Date.init) {
        self.repository = repository; self.http = http; self.now = now
    }

    func register(_ resource: ChatOriginalResource) { resources[resource.path] = resource }
    func invalidateSession() {
#if DEBUG
        httpQA?.invalidate()
        boundaryQA?.event("sessionInvalidated")
#endif
        valid = false; tickets.removeAll(); resources.removeAll(); expiryTimer?.invalidate()
        flights.values.forEach { $0.1.cancel() }; flights.removeAll()
    }
    func remove(path: String) {
#if DEBUG
        httpQA?.remove(path: path)
#endif
        removedPaths.insert(path); resources[path] = nil
        guard let request = try? ChatMediaURLRequest(path: path) else { return }
        tickets[request] = nil; flights.removeValue(forKey: request)?.1.cancel()
    }
    private func validate(_ resource: ChatOriginalResource) throws {
        try Task.checkCancellation()
        guard valid else { throw CancellationError() }
        guard !removedPaths.contains(resource.path) else { throw ChatVideoPlaybackError.unavailable }
        guard let expiry = resource.mediaExpiresAt, expiry > now() else { throw ChatVideoPlaybackError.expired }
        guard !resource.version.isEmpty else { throw ChatVideoPlaybackError.invalidResponse }
    }
    func ticket(for resource: ChatOriginalResource, forceRefresh: Bool = false) async throws -> ChatMediaURLTicket {
        try validate(resource)
        let request = try ChatMediaURLRequest(path: resource.path)
        prune()
        let ticket: ChatMediaURLTicket
        if !forceRefresh, let cached = tickets[request] { ticket = cached }
        else {
            let flight: (UUID, Task<ChatMediaURLTicket, Error>)
            if let existing = flights[request] { flight = existing }
            else {
                flight = (UUID(), Task {
                    let response = try await repository.issue(request)
#if DEBUG
                    if let boundaryQA, boundaryQA.matches(resource) {
                        try await boundaryQA.issued(request, ticket: response)
                    }
#endif
                    return response
                }); flights[request] = flight
            }
            do { ticket = try await flight.1.value }
            catch { if flights[request]?.0 == flight.0 { flights[request] = nil }; throw error }
            if flights[request]?.0 == flight.0 { flights[request] = nil }
        }
        do { try validate(resource) }
        catch {
#if DEBUG
            if let boundaryQA, boundaryQA.matches(resource) {
                boundaryQA.event("ticketRejected", details: "sessionValid=\(valid) cancelled=\(Task.isCancelled)")
            }
#endif
            throw error
        }
        guard ticket.urlExpiresAt > now(), ticket.urlExpiresAt <= ticket.mediaExpiresAt,
              ticket.urlExpiresAt.timeIntervalSince(now()) <= 3600,
              ticket.generation == resource.version,
              abs(ticket.mediaExpiresAt.timeIntervalSince(resource.mediaExpiresAt!)) < 0.001 else {
            throw ChatVideoPlaybackError.invalidResponse
        }
        tickets[request] = ticket
        scheduleExpiry()
#if DEBUG
        httpQA?.observe(resource: resource, ticket: ticket)
#endif
        return ticket
    }
    private func prune() { tickets = tickets.filter { $0.value.urlExpiresAt > now() && $0.value.mediaExpiresAt > now() } }
    private func scheduleExpiry() {
        expiryTimer?.invalidate(); expiryTimer = nil
        guard valid, let expiry = tickets.values.map(\.urlExpiresAt).min() else { return }
        expiryTimer = Timer.scheduledTimer(withTimeInterval: max(0.01, expiry.timeIntervalSince(now())), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.prune(); self?.scheduleExpiry() }
        }
        if let expiryTimer { RunLoop.main.add(expiryTimer, forMode: .common) }
    }
    func file(path: String, maxBytes: Int, to destination: URL) async throws {
        guard let resource = resources[path] else { throw ChatVideoPlaybackError.invalidResponse }
        try await file(resource: resource, maxBytes: maxBytes, to: destination)
    }
    func file(resource: ChatOriginalResource, maxBytes: Int, to destination: URL) async throws {
        for attempt in 0..<2 {
            let ticket = try await ticket(for: resource, forceRefresh: attempt > 0)
#if DEBUG
            try await boundaryQA?.beforeDownload(resource, ticket: ticket, attempt: attempt)
#endif
            let (temporary, status) = try await http.download(ticket.url)
            defer {
                try? FileManager.default.removeItem(at: temporary)
#if DEBUG
                if let boundaryQA, boundaryQA.matches(resource) {
                    boundaryQA.event("temporaryCleaned", details: "attempt=\(attempt) absent=\(!FileManager.default.fileExists(atPath: temporary.path))")
                }
#endif
            }
#if DEBUG
            try await boundaryQA?.received(resource, file: temporary, status: status, attempt: attempt)
#endif
            do { try validate(resource) }
            catch {
#if DEBUG
                if let boundaryQA, boundaryQA.matches(resource) {
                    boundaryQA.event("fileRejected", details: "sessionValid=\(valid) cancelled=\(Task.isCancelled)")
                }
#endif
                throw error
            }
            if attempt == 0, ticket.urlExpiresAt <= now(),
               ChatMediaHTTPErrorKind.classify(status: status, file: temporary).isExpiry(status: status) {
#if DEBUG
                if let boundaryQA, boundaryQA.matches(resource) { boundaryQA.event("renewing") }
#endif
                continue
            }
            guard (200..<300).contains(status) else { throw ChatVideoPlaybackError.temporarilyUnavailable }
            let bytes = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes > 0, bytes <= maxBytes else { throw ImageCachePipelineError.imageTooLarge }
            try FileManager.default.moveItem(at: temporary, to: destination)
#if DEBUG
            if let boundaryQA, boundaryQA.matches(resource) { boundaryQA.event("fileDelivered", details: "bytes=\(bytes)") }
#endif
            return
        }
        throw ChatVideoPlaybackError.temporarilyUnavailable
    }
    func data(path: String, maxBytes: Int) async throws -> Data {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try await self.file(path: path, maxBytes: maxBytes, to: file)
        return try Data(contentsOf: file)
    }
    deinit { expiryTimer?.invalidate(); flights.values.forEach { $0.1.cancel() } }
}

struct SignedChatVideoPlaybackURLRepository: ChatVideoPlaybackURLRepository {
    let service: ChatMediaSignedDownloadService
    func issue(for resource: ChatVideoPlaybackResource) async throws -> ChatVideoPlaybackURL {
        let ticket = try await service.ticket(for: resource.original, forceRefresh: true)
        return ChatVideoPlaybackURL(url: ticket.url, urlExpiresAt: ticket.urlExpiresAt, mediaExpiresAt: ticket.mediaExpiresAt)
    }
}
