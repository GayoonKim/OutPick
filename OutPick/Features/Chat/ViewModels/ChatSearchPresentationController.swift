import Foundation

/// 화면 이동을 직렬화하며 빠른 입력은 마지막 의도로 합친다. 스캔은 세션이 하나만 수행한다.
@MainActor final class ChatSearchPresentationController {
    typealias Loader = @MainActor (ChatSearchResultMetadata, ChatMessageSearchSource) async throws -> [ChatMessage]
    typealias Display = @MainActor ([ChatMessage], String, @escaping @MainActor () -> Bool) async -> Bool
    private let roomID: String
    private let session: any ChatRoomSearchSessionUseCaseProtocol
    private let load: Loader
    private var observer: UUID?
    private var worker: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var queued: (direction: ChatSearchDirection, prefetch: Bool)?
    private var retryMovement: (direction: ChatSearchDirection, prefetch: Bool) = (.older, false)
    private var paused = false
    private var moving = false
    private var movementFailed = false
    private(set) var keyword: String?
    private(set) var snapshot: ChatSearchSessionSnapshot?
    var onChange: (@MainActor () -> Void)?
    var display: Display?
    var state: ChatSearchPresentationState { ChatSearchPresentationState(snapshot: snapshot, moving: moving, movementFailed: movementFailed) }
    var highlightedID: String? { snapshot?.isRefreshing == false ? snapshot?.selectedMessageID : nil }
    var isActive: Bool { keyword != nil }

    init(roomID: String, session: any ChatRoomSearchSessionUseCaseProtocol, load: @escaping Loader) {
        self.roomID = roomID; self.session = session; self.load = load
        observer = session.observe { [weak self] in self?.receive($0) }
    }
    deinit {
        worker?.cancel()
        let session = session; let identity = snapshot?.identity; let observer = observer
        Task { @MainActor in
            if let observer { session.removeObserver(observer) }
            if let identity { await session.cancel(session: identity) }
        }
    }
    func start(_ text: String) {
        stop()
        guard !ChatMessageSearchIndex.normalize(text).isEmpty else { return }
        keyword = text; paused = false
        session.setForeground(true)
        session.search(roomID: roomID, keyword: text)
    }
    func stop() {
        generation &+= 1; queued = nil; movementFailed = false; keyword = nil
        if snapshot?.identity == session.snapshot?.identity { session.stop() }
        snapshot = nil; onChange?()
    }
    func suspend() { paused = true; generation &+= 1; queued = nil; session.setForeground(false) }
    func resume() {
        guard isActive else { return }
        paused = false; session.setForeground(true)
    }
    func move(_ direction: ChatSearchDirection, prefetch: Bool = true) {
        guard isActive, !paused else { return }
        generation &+= 1; queued = (direction, prefetch); retryMovement = (direction, prefetch); movementFailed = false
        launch()
    }
    func retry() {
        if movementFailed { move(retryMovement.direction, prefetch: retryMovement.prefetch) }
        else if case .failed = snapshot?.count { session.retry() }
        else if let snapshot, state.canContinue {
            session.continueSearch(session: snapshot.identity)
            move(.older, prefetch: false)
        }
        else if let keyword { start(keyword) }
    }
    private func receive(_ value: ChatSearchSessionSnapshot?) {
        guard isActive else { return }
        guard value == nil || value?.identity.roomID == roomID else { return }
        let invalidated = value?.identity != snapshot?.identity || value?.visibilityRevision != snapshot?.visibilityRevision
            || value?.isRefreshing == true || value?.isPaused == true
        if invalidated { generation &+= 1; queued = nil; movementFailed = false }
        snapshot = value
        onChange?()
        guard !paused, let value, !value.isRefreshing, !value.isPaused else { return }
        if case .failed = value.count { return }
        if value.selectedMessageID == nil, !movementFailed, !moving, queued == nil {
            switch value.count {
            case .scanning(let count), .completed(let count): if count > 0 { move(.older, prefetch: false) }
            default: break
            }
        }
    }
    private func launch() {
        guard worker == nil, !paused else { return }
        worker = Task { [weak self] in await self?.drain() }
    }
    private func drain() async {
        defer {
            worker = nil; moving = false; onChange?()
            // 차단/삭제·fallback이 진행 중 이동을 무효화했다면 새 유효 세대에서 자동 선택한다.
            if let snapshot, !movementFailed, !paused, isActive, snapshot.selectedMessageID == nil,
               !snapshot.isRefreshing, !snapshot.isPaused {
                let count: Int
                switch snapshot.count { case .scanning(let n), .completed(let n): count = n; default: count = 0 }
                if count > 0, queued == nil { queued = (.older, false) }
            }
            if queued != nil { launch() }
        }
        while let movement = queued, !paused, isActive {
            queued = nil
            let request = generation
            guard let current = snapshot else { return }
            moving = true; onChange?()
            let valid = { [weak self] in
                guard let self else { return false }
                return self.isActive && !self.paused && self.generation == request
                    && self.snapshot?.identity == current.identity && self.snapshot?.isRefreshing == false
                    && self.snapshot?.isPaused == false
            }
            do {
                guard let pending = try await session.prepareNavigation(session: current.identity, direction: movement.direction), valid() else { continue }
                let messages = try await load(pending.target, current.source)
                guard valid() else { continue }
                guard messages.contains(where: { $0.ID == pending.target.messageID && !$0.isDeleted }),
                      let display, await display(messages, pending.target.messageID, valid), valid() else {
                    if valid() { movementFailed = true }; continue
                }
                try await session.commitNavigation(pending)
                if valid(), movement.prefetch, movement.direction == .older {
                    session.prefetchIfNeeded(session: current.identity)
                }
            } catch {
                if valid() {
                    if let failure = error as? ChatSearchFailure, failure == .accessLost || failure == .roomClosed {
                        // 새 검색이 끼어들기 전에 현재 세션 종료와 실패 상태 발행을 함께 처리한다.
                        if session.snapshot?.identity == current.identity { session.stop() }
                        snapshot = ChatSearchSessionSnapshot(identity: current.identity, source: current.source,
                            visibilityRevision: current.visibilityRevision, count: .failed(failure), selectedMessageID: nil, committedOrdinal: nil)
                        onChange?()
                    } else { movementFailed = true }
                }
            }
        }
    }
}
