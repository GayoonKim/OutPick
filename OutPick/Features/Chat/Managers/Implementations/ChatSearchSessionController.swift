import Foundation

@MainActor final class ChatSearchSessionController: ChatSearchSessionManaging {
    let store: any ChatSearchPersisting
    let remote: any ChatSearchCandidateReading
    let local: any ChatSearchLocalReading
    let visibility: (any UserBlockVisibilityObserving)?
    let validation: any ChatSearchValidating
    let network: any NetworkStatusProviding
    let deletionFence: ChatSearchDeletionFence
    var active: ChatSearchRun?
    var foreground = true
    private(set) var snapshot: ChatSearchSessionSnapshot?
    private var observers: [UUID: @MainActor (ChatSearchSessionSnapshot?) -> Void] = [:]
    private var visibilityObserver: UUID?
    private var deletionObserver: UUID?
    private var generation: UInt64 = 0
    lazy var navigation = ChatSearchNavigator(owner: self)

    init(remote: any ChatSearchCandidateReading, local: any ChatSearchLocalReading,
         store: any ChatSearchPersisting, visibility: (any UserBlockVisibilityObserving)?,
         validation: any ChatSearchValidating, network: any NetworkStatusProviding, deletionFence: ChatSearchDeletionFence) {
        self.remote = remote; self.local = local; self.store = store; self.visibility = visibility
        self.validation = validation; self.network = network; self.deletionFence = deletionFence
    }

    @discardableResult func observe(_ callback: @escaping @MainActor (ChatSearchSessionSnapshot?) -> Void) -> UUID {
        let id = UUID(); observers[id] = callback; callback(snapshot); return id
    }
    func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }

    func search(roomID: String, keyword: String) {
        stop()
        guard !ChatMessageSearchIndex.normalize(keyword).isEmpty, let value = visibility?.snapshot(),
              let account = value.accountID, value.isReady else { return }
        generation &+= 1
        let run = ChatSearchRun(identity: ChatSearchSessionIdentity(sessionID: UUID(), accountID: account,
            accountEpoch: value.accountEpoch, roomID: roomID, generation: generation), keyword: keyword,
            source: network.currentStatus.isOnline ? .serverIndex : .localOffline, visibility: value)
        active = run
        visibilityObserver = visibility?.observe { [weak self] in self?.receiveVisibility($0) }
        deletionObserver = deletionFence.observe { [weak self] room in
            guard let self, let run = self.active, run.identity.roomID == room else { return }
            run.needsValidation = true
            self.invalidate(run)
            self.kick(run)
        }
        invalidate(run)
        kick(run)
    }

    func stop() {
        let old = active; active = nil
        old?.task?.cancel(); old?.wake(); navigation.invalidate()
        if let id = visibilityObserver { visibility?.removeObserver(id) }; visibilityObserver = nil
        if let id = deletionObserver { deletionFence.removeObserver(id) }; deletionObserver = nil
        emit(nil)
        if let old {
            let id = old.identity; let retired = old.retiredIdentity
            Task { try? await store.closeSession(identity: id); if let retired { try? await store.closeSession(identity: retired) } }
        }
    }
    func cancel(session: ChatSearchSessionIdentity) async { if active?.identity == session { stop() } }

    func continueSearch(session: ChatSearchSessionIdentity) { requestPages(session: session, count: 5) }

    func prefetchIfNeeded(session: ChatSearchSessionIdentity) {
        guard let snapshot, snapshot.identity == session, let ordinal = snapshot.committedOrdinal,
              case .scanning(let count) = snapshot.count, count - ordinal <= 10 else { return }
        requestPages(session: session, count: 1)
    }

    private func requestPages(session: ChatSearchSessionIdentity, count: Int) {
        guard let run = active, run.identity == session, valid(run), foreground, run.failure == nil,
              !run.exhausted, run.pagesRemaining == 0, snapshot?.isRefreshing == false else { return }
        run.pagesRemaining = count
        if var current = snapshot { current.isFetching = true; emit(current) }
        kick(run)
    }

    func retry() {
        guard let run = active, let failure = run.failure else { return }
        if failure == .localStorage {
            run.failure = nil; run.needsValidation = true; invalidate(run); kick(run)
        } else { search(roomID: run.identity.roomID, keyword: run.keyword) }
    }

    func setForeground(_ value: Bool) {
        foreground = value
        guard let run = active else { return }
        navigation.invalidate(); run.wake()
        if value { run.needsValidation = true; invalidate(run); kick(run) }
        else if var current = snapshot { current.isPaused = true; emit(current) }
    }

    func receiveVisibility(_ value: UserBlockVisibilitySnapshot) {
        guard let run = active else { return }
        guard value.accountID == run.identity.accountID, value.accountEpoch == run.identity.accountEpoch, value.isReady else {
            terminate(run, failure: .accessLost); return
        }
        guard value.revision > run.visibility.revision else { return }
        run.visibility = value
        run.blockedAuthors.formUnion(value.blockedIDs)
        invalidate(run); kick(run)
    }

    func valid(_ run: ChatSearchRun) -> Bool {
        guard active === run, let value = visibility?.snapshot() else { return false }
        return value.accountID == run.identity.accountID && value.accountEpoch == run.identity.accountEpoch && value.isReady
    }

    func invalidate(_ run: ChatSearchRun, preservingSelection: Bool = false) {
        guard active === run else { return }
        let selection = preservingSelection ? snapshot : nil
        run.publicationRevision &+= 1; navigation.invalidate(); run.wake()
        run.shouldPublish = run.created
        emit(ChatSearchSessionSnapshot(identity: run.identity, source: run.source,
            visibilityRevision: run.visibility.revision, count: run.failure.map(ChatSearchCountState.failed) ?? .unknown,
            selectedMessageID: selection?.selectedMessageID, committedOrdinal: selection?.committedOrdinal,
            isRefreshing: !preservingSelection, isPaused: !foreground))
    }

    func emit(_ value: ChatSearchSessionSnapshot?) {
        snapshot = value
        for callback in Array(observers.values) { callback(value) }
    }

    func kick(_ run: ChatSearchRun) {
        guard valid(run), foreground, run.failure == nil, run.task == nil else { return }
        run.task = Task { await self.drive(run) }
    }

    private func drive(_ run: ChatSearchRun) async {
        var resume = false
        defer { run.task = nil; run.wake(); if resume { kick(run) } }
        do {
            while valid(run), !Task.isCancelled {
                if !foreground { return }
                if let retired = run.retiredIdentity { try await store.closeSession(identity: retired); run.retiredIdentity = nil }
                if run.scope == nil { try await open(run) }
                else if !run.created { try await create(run) }
                guard valid(run), !Task.isCancelled else { return }
                if run.needsValidation {
                    await deletionFence.waitForWrites(roomID: run.identity.roomID)
                    guard valid(run), foreground, !Task.isCancelled else { return }
                    let publication = run.publicationRevision
                    let deletionRevision = deletionFence.revision(roomID: run.identity.roomID)
                    if run.source == .serverIndex, !network.currentStatus.isOnline { throw ChatSearchFailure.transientNetwork }
                    if network.currentStatus.isOnline {
                        do {
                            try await validation.validateAccess(accountID: run.identity.accountID, roomID: run.identity.roomID)
                            try await validation.reconcileDeletion(accountID: run.identity.accountID, roomID: run.identity.roomID)
                            deletionFence.reconciled(roomID: run.identity.roomID, through: deletionRevision)
                        } catch ChatSearchFailure.transientNetwork where run.source != .serverIndex {
                            // 이미 로컬인 결과는 제한 안내를 유지한다. 권한 오류는 이 경로로 우회하지 않는다.
                        }
                    }
                    guard valid(run) else { return }
                    if publication != run.publicationRevision { continue }
                    run.needsValidation = false
                }
                try await syncVisibility(run)
                guard valid(run), foreground else { return }
                if run.shouldPublish || run.exhausted {
                    guard try await publish(run) else { continue }
                    if run.exhausted { run.local = nil; return }
                }
                guard valid(run), foreground, !run.needsValidation, !Task.isCancelled else { continue }
                if run.pagesRemaining == 0 { return }
                if run.pending == nil {
                    guard let scope = run.scope else { throw ChatSearchFailure.invalidRequest }
                    if run.source == .serverIndex {
                        run.pending = try await remote.fetchSearchCandidatePage(scope: scope, after: run.cursor, limit: 100)
                    } else {
                        guard let local = run.local else { throw ChatSearchFailure.localStorage }
                        do { run.pending = try await local.page(upperSeq: scope.upperSeq, after: run.cursor, limit: 100) }
                        catch { throw ChatSearchFailure.localStorage }
                    }
                }
                guard valid(run), !Task.isCancelled else { return }
                if run.source == .serverIndex {
                    try await validation.reconcileDeletion(accountID: run.identity.accountID, roomID: run.identity.roomID)
                }
                try await commit(run)
                guard valid(run) else { return }
                if foreground { _ = try await publish(run) }
                if !foreground { return }
            }
        } catch is CancellationError {
            // 교체된 세대의 응답·cursor·후속 조회는 공개하지 않는다.
            if valid(run), !Task.isCancelled { fail(run, .transientNetwork) }
        } catch {
            guard valid(run) else { return }
            let failure = (error as? ChatSearchFailure) ?? .localStorage
            if failure == .transientNetwork, run.source == .serverIndex {
                do {
                    try await fallback(run)
                    // 같은 worker 안에서 전환을 끝내고 이후 루프는 새 task 하나로 재개한다.
                    resume = true
                } catch { fail(run, .localStorage) }
            } else if failure == .accessLost || failure == .roomClosed { terminate(run, failure: failure) }
            else { fail(run, failure) }
        }
    }

    private func open(_ run: ChatSearchRun) async throws {
        let upper: Int64
        if run.source == .serverIndex {
            try await validation.validateAccess(accountID: run.identity.accountID, roomID: run.identity.roomID)
            upper = try await remote.fetchSearchUpperSequence(roomID: run.identity.roomID)
        } else {
            do {
                run.local = try await local.openSearchSnapshot(roomID: run.identity.roomID)
                if let fixed = run.upperBound { upper = fixed }
                else { upper = try await run.local!.upperSequence() }
            } catch { throw ChatSearchFailure.localStorage }
        }
        guard valid(run), !Task.isCancelled else { throw CancellationError() }
        run.upperBound = upper
        run.scope = try ChatSearchScope(identity: run.identity, keyword: run.keyword, upperSeq: upper, source: run.source)
        try await create(run)
    }

    private func create(_ run: ChatSearchRun) async throws {
        guard let scope = run.scope else { throw ChatSearchFailure.invalidRequest }
        do { try await store.createSession(scope: scope, visibilityRevision: run.visibility.revision, blockedAuthorIDs: run.blockedAuthors) }
        catch { throw ChatSearchFailure.localStorage }
        run.created = true
        guard valid(run), !Task.isCancelled else {
            try? await store.closeSession(identity: scope.identity); throw CancellationError()
        }
        run.appliedVisibility = nil
    }

    private func fallback(_ run: ChatSearchRun) async throws {
        let old = run.identity
        let upper = run.scope?.upperSeq
        run.preferredID = run.selected?.messageID
        run.replacementAnchor = nil
        run.selected = nil; run.pending = nil; run.cursor = nil; run.exhausted = false
        run.pagesRemaining = 5
        generation &+= 1
        run.identity = ChatSearchSessionIdentity(sessionID: UUID(), accountID: old.accountID,
            accountEpoch: old.accountEpoch, roomID: old.roomID, generation: generation)
        run.source = .localFallbackAfterServerFailure; run.scope = nil; run.created = false
        run.retiredIdentity = old
        invalidate(run)
        try await store.closeSession(identity: old)
        run.retiredIdentity = nil
        guard valid(run), !Task.isCancelled else { throw CancellationError() }
        run.local = try await local.openSearchSnapshot(roomID: old.roomID)
        let bound: Int64
        if let upper { bound = upper } else { bound = try await run.local!.upperSequence() }
        run.upperBound = bound
        run.scope = try ChatSearchScope(identity: run.identity, keyword: run.keyword, upperSeq: bound, source: run.source)
        try await create(run)
        run.needsValidation = false // 네트워크 실패로 전환했으므로 자동 원격 재시도하지 않는다.
    }

    private func syncVisibility(_ run: ChatSearchRun) async throws {
        while valid(run), run.appliedVisibility != run.visibility.revision {
            let snapshot = run.visibility
            do { _ = try await store.applyVisibility(identity: run.identity, revision: snapshot.revision, blockedAuthorIDs: run.blockedAuthors) }
            catch { throw ChatSearchFailure.localStorage }
            guard valid(run) else { throw CancellationError() }
            run.appliedVisibility = snapshot.revision
        }
    }

    private func commit(_ run: ChatSearchRun) async throws {
        guard let page = run.pending, let scope = run.scope, page.candidates.count <= 100 else { throw ChatSearchFailure.malformedData }
        let hits = page.candidates.filter {
            guard let type = $0.messageType else { return false }
            return !$0.isDeleted && $0.seq > 0 && $0.seq <= scope.upperSeq && [.text, .image, .video].contains(type)
                && ChatMessageSearchIndex.contains($0.msg, keyword: scope.normalizedQuery)
        }.map { ChatSearchResultMetadata(messageID: $0.ID, seq: $0.seq, senderUID: $0.senderUID) }
        while valid(run), !Task.isCancelled {
            try await syncVisibility(run)
            do {
                let stored = try await store.commitPage(identity: run.identity, visibilityRevision: run.visibility.revision,
                    expectedCursor: run.cursor, hits: hits, nextCursor: page.nextCursor, isExhausted: page.isExhausted)
                run.cursor = stored.cursor; run.exhausted = stored.isExhausted; run.pending = nil
                run.pagesRemaining = stored.insertedCount > 0 || stored.isExhausted ? 0 : max(0, run.pagesRemaining - 1)
                run.resultRevision &+= 1
                run.shouldPublish = true
                return
            } catch ChatSearchPersistenceError.visibilityChanged { run.appliedVisibility = nil }
            catch { throw ChatSearchFailure.localStorage }
        }
        throw CancellationError()
    }

    @discardableResult func publish(_ run: ChatSearchRun) async throws -> Bool {
        guard valid(run), foreground, !run.needsValidation else { return false }
        await deletionFence.waitForWrites(roomID: run.identity.roomID)
        guard valid(run), foreground, !run.needsValidation else { return false }
        try deletionFence.requireHealthy(roomID: run.identity.roomID)
        try await syncVisibility(run)
        let revision = run.publicationRevision
        let state = try await store.state(identity: run.identity)
        let ordinal: Int?
        if let selected = run.selected { ordinal = try await store.ordinal(identity: run.identity, messageID: selected.messageID) }
        else { ordinal = nil }
        guard valid(run), foreground, !run.needsValidation, revision == run.publicationRevision,
              state.visibilityRevision == run.visibility.revision else { return false }
        if ordinal == nil {
            if let selected = run.selected { run.replacementAnchor = selected }
            run.selected = nil
        }
        run.shouldPublish = false
        emit(ChatSearchSessionSnapshot(identity: run.identity, source: run.source, visibilityRevision: state.visibilityRevision,
            count: state.isExhausted ? .completed(totalCount: state.count) : .scanning(knownCount: state.count),
            selectedMessageID: run.selected?.messageID, committedOrdinal: ordinal,
            isFetching: run.pagesRemaining > 0 && !run.exhausted))
        run.wake()
        return true
    }

    private func fail(_ run: ChatSearchRun, _ failure: ChatSearchFailure) {
        guard active === run else { return }
        let preserve = failure == .localStorage && snapshot?.isRefreshing == false
            && snapshot?.visibilityRevision == run.visibility.revision && !run.needsValidation
        run.failure = failure; invalidate(run, preservingSelection: preserve)
    }
    private func terminate(_ run: ChatSearchRun, failure: ChatSearchFailure) {
        guard active === run else { return }
        let value = ChatSearchSessionSnapshot(identity: run.identity, source: run.source, visibilityRevision: run.visibility.revision,
            count: .failed(failure), selectedMessageID: nil, committedOrdinal: nil)
        stop(); emit(value)
    }

    func prepareNavigation(session: ChatSearchSessionIdentity, direction: ChatSearchDirection) async throws -> ChatSearchPendingNavigation? {
        try await navigation.prepare(session: session, direction: direction)
    }
    func commitNavigation(_ navigation: ChatSearchPendingNavigation) async throws { try await self.navigation.commit(navigation) }
}
