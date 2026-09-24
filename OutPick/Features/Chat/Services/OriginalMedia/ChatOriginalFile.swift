import Foundation

struct ChatOriginalResource: Hashable, Sendable {
    let path: String
    let version: String
    let maximumBytes: Int

    init(path: String, version: String = "path-v1", maximumBytes: Int = ChatPhotoSizePolicy.maximumFileBytes) {
        self.path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        self.version = version
        self.maximumBytes = maximumBytes
    }

    var fileExtension: String {
        let value = URL(string: path)?.pathExtension.lowercased() ?? ""
        return ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "mp4", "mov", "m4v"].contains(value) ? value : "bin"
    }
}

enum ChatOriginalPurpose: Sendable { case viewing, adjacent, saving, playback }

/// 세션 종료와 완료 콜백 사이에도 동기적으로 읽을 수 있는 무효화 경계다.
final class ChatOriginalValidity: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true
    var isValid: Bool { lock.lock(); defer { lock.unlock() }; return valid }
    func invalidate() { lock.lock(); valid = false; lock.unlock() }
}

final class ChatOriginalSession: @unchecked Sendable {
    let id = UUID()
    let validity = ChatOriginalValidity()
    let storeGeneration: UInt64
    init(storeGeneration: UInt64) { self.storeGeneration = storeGeneration }
}

final class ChatOriginalGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    var value: UInt64 { lock.lock(); defer { lock.unlock() }; return generation }
    func advance() { lock.lock(); generation &+= 1; lock.unlock() }
}

/// 반환된 파일을 사용하는 동안 보관한다. 명시적 release와 deinit은 중복 해제하지 않는다.
final class ChatOriginalFileLease: @unchecked Sendable {
    let fileURL: URL
    private let lock = NSLock()
    private var releaseAction: (@Sendable () async -> Void)?
    private let valid: @Sendable () -> Bool

    init(fileURL: URL, isValid: @escaping @Sendable () -> Bool,
         release: @escaping @Sendable () async -> Void) {
        self.fileURL = fileURL
        self.valid = isValid
        self.releaseAction = release
    }

    var isValid: Bool {
        lock.lock(); defer { lock.unlock() }
        return releaseAction != nil && valid()
    }

    private func takeRelease() -> (@Sendable () async -> Void)? {
        lock.lock(); defer { lock.unlock() }
        defer { releaseAction = nil }
        return releaseAction
    }

    func release() async { await takeRelease()?() }
    deinit { if let action = takeRelease() { Task { await action() } } }
}

protocol ChatOriginalFileLoading: AnyObject {
    func acquireOriginal(_ resource: ChatOriginalResource, purpose: ChatOriginalPurpose) async throws -> ChatOriginalFileLease
    func cachedOriginal(_ resource: ChatOriginalResource) async throws -> ChatOriginalFileLease?
    func removeOriginal(path: String) async
    func invalidateSession()
}

final class ChatOriginalFileService: ChatOriginalFileLoading, @unchecked Sendable {
    private let accountID: String
    private let session: ChatOriginalSession
    private let store: ChatOriginalFileStore
    private let transport: any ChatOriginalFileTransport

    init(accountID: String, store: ChatOriginalFileStore, transport: any ChatOriginalFileTransport) {
        self.accountID = accountID
        self.store = store
        self.transport = transport
        self.session = ChatOriginalSession(storeGeneration: store.generation.value)
    }

    func acquireOriginal(_ resource: ChatOriginalResource, purpose: ChatOriginalPurpose) async throws -> ChatOriginalFileLease {
        let priority: ImageRequestPriority
        if case .adjacent = purpose { priority = .prefetch } else { priority = .visible }
        return try await ImageWorkContext.$current.withValue(ImageWorkContext(priority)) {
            try await store.acquire(resource, accountID: accountID, session: session, transport: transport)
        }
    }

    func cachedOriginal(_ resource: ChatOriginalResource) async throws -> ChatOriginalFileLease? {
        try await store.cached(resource, accountID: accountID, session: session)
    }

    func removeOriginal(path: String) async { await store.remove(path: path, accountID: accountID) }

    func invalidateSession() {
        session.validity.invalidate()
        let store = store, id = session.id
        Task { await store.endSession(id) }
    }

    deinit { invalidateSession() }
}
