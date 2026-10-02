import Foundation

protocol ChatDeletionMediaCleaning {
    func clean(_ item: ChatDeletionCleanupItem) async throws
}

final class DefaultChatDeletionMediaCleaner: ChatDeletionMediaCleaning {
    private let imageLoader: ChatAttachmentImageLoading
    private let videoDiskCache: ChatVideoDiskCaching
    private let storageURLResolver: ChatStorageURLResolving
    private let fileManager: FileManager
    private let originalFiles: (any ChatOriginalFileLoading)?

    init(
        imageLoader: ChatAttachmentImageLoading,
        videoDiskCache: ChatVideoDiskCaching,
        storageURLResolver: ChatStorageURLResolving,
        fileManager: FileManager = .default,
        originalFiles: (any ChatOriginalFileLoading)? = nil
    ) {
        self.imageLoader = imageLoader
        self.videoDiskCache = videoDiskCache
        self.storageURLResolver = storageURLResolver
        self.fileManager = fileManager
        self.originalFiles = originalFiles
    }

    func clean(_ item: ChatDeletionCleanupItem) async throws {
        switch item.kind {
        case .image:
            await originalFiles?.removeOriginal(path: item.path)
            await imageLoader.removeCachedImage(for: item.path)
            await storageURLResolver.removeCachedURL(for: item.path)
        case .video:
            await originalFiles?.removeOriginal(path: item.path)
            await videoDiskCache.remove(forKey: item.path)
            await storageURLResolver.removeCachedURL(for: item.path)
        case .localFile:
            guard let url = Self.localURL(from: item.path) else { return }
            let sandbox = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
            let target = url.standardizedFileURL.path
            guard target == sandbox || target.hasPrefix(sandbox + "/") else { return }
            if fileManager.fileExists(atPath: target) {
                try fileManager.removeItem(atPath: target)
            }
        }
    }

    private static func localURL(from path: String) -> URL? {
        if path.hasPrefix("file://") { return URL(string: path) }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return nil
    }
}

protocol ChatDeletionMessageSanitizing: AnyObject {
    func sanitize(_ messages: [ChatMessage], accountID: String, roomID: String) async throws -> [ChatMessage]
}

protocol ChatDeletionSyncUseCaseProtocol: ChatDeletionMessageSanitizing {
    func reconcile(
        roomID: String,
        accountID: String,
        allowEmptyLocalBootstrap: Bool
    ) async throws -> Set<String>
    func handleSocketEvent(_ event: ChatDeletionSocketEvent, accountID: String) async throws -> Set<String>
    func resumePendingCleanup() async
}

actor ChatDeletionSyncUseCase: ChatDeletionSyncUseCaseProtocol {
    private let repository: ChatDeletionSyncRepositoryProtocol
    private let persistence: ChatDeletionSyncPersisting
    private let mediaCleaner: ChatDeletionMediaCleaning
    private let pageSize: Int
    private let searchFence: ChatSearchDeletionFence?
    private struct RoomKey: Hashable { let accountID: String; let roomID: String }
    private struct ReplyKey: Hashable { let accountID: String; let roomID: String; let ids: [String] }
    private var reconciliations: [RoomKey: (UUID, Task<Set<String>, Error>)] = [:]
    private var targetRevisions: [RoomKey: Int64] = [:]
    private var replyQueries: [ReplyKey: (UUID, Task<[ChatDeletionDelta], Error>)] = [:]
    private var cleanupTask: Task<Void, Never>?
    private var cleanupPending: [ChatDeletionCleanupItem] = []

    #if DEBUG
    // 경합 QA에서 이벤트 접수 완료를 확인해 임의 sleep 없이 조회를 재개한다.
    func pendingRevisionForDebug(accountID: String, roomID: String) -> Int64? {
        targetRevisions[RoomKey(accountID: accountID, roomID: roomID)]
    }
    #endif

    init(
        repository: ChatDeletionSyncRepositoryProtocol,
        persistence: ChatDeletionSyncPersisting,
        mediaCleaner: ChatDeletionMediaCleaning,
        pageSize: Int = 100,
        searchFence: ChatSearchDeletionFence? = nil
    ) {
        self.repository = repository
        self.persistence = persistence
        self.mediaCleaner = mediaCleaner
        self.pageSize = max(1, min(pageSize, 100))
        self.searchFence = searchFence
    }

    func reconcile(
        roomID: String,
        accountID: String,
        allowEmptyLocalBootstrap: Bool
    ) async throws -> Set<String> {
        let key = RoomKey(accountID: accountID, roomID: roomID)
        if let task = reconciliations[key] { return try await task.1.value }
        let id = UUID()
        let task = Task { try await self.performReconcile(roomID: roomID, accountID: accountID,
            allowEmptyLocalBootstrap: allowEmptyLocalBootstrap) }
        reconciliations[key] = (id, task)
        defer {
            if reconciliations[key]?.0 == id {
                reconciliations.removeValue(forKey: key)
                targetRevisions.removeValue(forKey: key)
            }
        }
        return try await task.value
    }

    private func performReconcile(roomID: String, accountID: String, allowEmptyLocalBootstrap: Bool) async throws -> Set<String> {
        let key = RoomKey(accountID: accountID, roomID: roomID)
        var head = try await repository.headRevision(roomID: roomID)
        head = max(head, targetRevisions[key] ?? head)
        guard head >= 0 else { throw ChatDeletionSyncError.invalidHead }
        var cursor = try await persistence.cursor(accountID: accountID, roomID: roomID)
        head = max(head, targetRevisions[key] ?? head)
        guard head > cursor else {
            await resumePendingCleanup()
            return []
        }

        if cursor == 0,
           allowEmptyLocalBootstrap,
           !(try await persistence.hasServerMessages(accountID: accountID, roomID: roomID)) {
            try await persistence.bootstrapCursor(head, accountID: accountID, roomID: roomID)
            await resumePendingCleanup()
            return []
        }

        var applied = Set<String>()
        while cursor < max(head, targetRevisions[key] ?? head) {
            head = max(head, targetRevisions[key] ?? head)
            let page = try await repository.deltas(
                roomID: roomID,
                afterRevision: cursor,
                limit: pageSize
            ).filter { $0.revision <= head }

            let usable: [ChatDeletionDelta]
            if page.first?.revision == cursor + 1 {
                usable = contiguousPrefix(page, after: cursor)
            } else {
                usable = try await recoverFromLocalMessages(accountID: accountID, roomID: roomID, after: cursor, head: head)
            }
            guard !usable.isEmpty else {
                throw ChatDeletionSyncError.revisionGap(expected: cursor + 1, actual: page.first?.revision)
            }

            let cleanup = try await applyWithSearchFence(usable, accountID: accountID, roomID: roomID)
            applied.formUnion(usable.map(\.messageID))
            cursor = usable.last?.revision ?? cursor
            await clean(cleanup)
        }

        guard cursor == head else {
            throw ChatDeletionSyncError.revisionGap(expected: cursor + 1, actual: nil)
        }
        return applied
    }

    func handleSocketEvent(_ event: ChatDeletionSocketEvent, accountID: String) async throws -> Set<String> {
        let key = RoomKey(accountID: accountID, roomID: event.roomID)
        let revision: Int64
        switch event.kind {
        case .message(let delta): revision = delta.revision
        case .headAdvanced(_, let toRevision): revision = toRevision
        }
        if let running = reconciliations[key] {
            targetRevisions[key] = max(targetRevisions[key] ?? 0, revision)
            let applied = try await running.1.value
            // 빈 결과/초기 bootstrap 종료 직전에 접수된 이벤트도 이번 호출에서 반영한다.
            let cursor = try await persistence.cursor(accountID: accountID, roomID: event.roomID)
            guard cursor < revision else { return applied }
            if reconciliations[key]?.0 == running.0 {
                reconciliations.removeValue(forKey: key)
                targetRevisions.removeValue(forKey: key)
            }
            return try await applied.union(handleSocketEvent(event, accountID: accountID))
        }
        let cursor = try await persistence.cursor(accountID: accountID, roomID: event.roomID)
        switch event.kind {
        case .message(let delta) where delta.revision == cursor + 1:
            let cleanup = try await applyWithSearchFence([delta], accountID: accountID, roomID: event.roomID)
            await clean(cleanup)
            return [delta.messageID]
        case .message(let delta) where delta.revision <= cursor:
            return []
        case .message, .headAdvanced:
            return try await reconcile(
                roomID: event.roomID,
                accountID: accountID,
                allowEmptyLocalBootstrap: false
            )
        }
    }

    func resumePendingCleanup() async {
        guard let items = try? await persistence.pendingCleanupItems() else { return }
        await clean(items)
    }

    func sanitize(
        _ messages: [ChatMessage],
        accountID: String,
        roomID: String
    ) async throws -> [ChatMessage] {
        // 서버가 직접 반환한 tombstone의 표시 정책을 로컬 legacy marker보다 먼저 반영한다.
        // 오래된 visible 메시지는 이 분기에 들어오지 않으므로 기존 marker의 재노출 차단은 유지된다.
        let pageByID = Dictionary(
            messages.map { ($0.ID, $0) },
            uniquingKeysWith: { current, candidate in
                if candidate.isDeleted != current.isDeleted {
                    return candidate.isDeleted ? candidate : current
                }
                return (candidate.deletionRevision ?? 0) >= (current.deletionRevision ?? 0)
                    ? candidate
                    : current
            }
        )
        var resolvedDeleted: [ChatDeletionDelta] = messages.compactMap { message in
            guard message.isDeleted, let revision = message.deletionRevision else { return nil }
            return ChatDeletionDelta(
                messageID: message.ID,
                roomID: roomID,
                seq: message.seq,
                revision: revision,
                deletedAt: message.deletedAt,
                anonymizesSender: message.senderUID.isEmpty
            )
        }
        var unknownReplyTargetIDs = Set<String>()
        for message in messages {
            guard let preview = message.replyPreview, !preview.isDeleted else { continue }
            if let target = pageByID[preview.messageID] {
                if target.isDeleted, let revision = target.deletionRevision {
                    resolvedDeleted.append(ChatDeletionDelta(
                        messageID: target.ID,
                        roomID: roomID,
                        seq: target.seq,
                        revision: revision,
                        deletedAt: target.deletedAt,
                        anonymizesSender: target.senderUID.isEmpty
                    ))
                }
            } else {
                unknownReplyTargetIDs.insert(preview.messageID)
            }
        }

        if !unknownReplyTargetIDs.isEmpty {
            resolvedDeleted.append(contentsOf: try await sharedReplyDeltas(
                accountID: accountID,
                roomID: roomID,
                messageIDs: Array(unknownReplyTargetIDs)
            ))
        }

        if !resolvedDeleted.isEmpty {
            let unique = Dictionary(
                resolvedDeleted.map { ($0.messageID, $0) },
                uniquingKeysWith: { lhs, rhs in lhs.revision >= rhs.revision ? lhs : rhs }
            ).values.map { $0 }
            let cleanup = try await applyWithSearchFence(unique, accountID: accountID, roomID: roomID, resolved: true)
            await clean(cleanup)
        }
        return try await persistence.sanitize(
            messages,
            accountID: accountID,
            roomID: roomID
        )
    }

    private func applyWithSearchFence(_ deltas: [ChatDeletionDelta], accountID: String, roomID: String,
                                      resolved: Bool = false) async throws -> [ChatDeletionCleanupItem] {
        // 이미 영속 반영한 주변 tombstone은 정리를 반복해도 검색 선택을 다시 시작하지 않는다.
        // 신규 삭제와 marker 정책 교정은 기존처럼 쓰기 전에 동기 무효화한다.
        let needsFence = resolved
            ? try await persistence.requiresResolvedDeletionFence(deltas, accountID: accountID, roomID: roomID)
            : true
        let token = needsFence ? await searchFence?.begin(roomID: roomID) : nil
        do {
            let items: [ChatDeletionCleanupItem]
            if resolved { items = try await persistence.recordResolvedDeletions(deltas, accountID: accountID, roomID: roomID) }
            else { items = try await persistence.apply(deltas, accountID: accountID, roomID: roomID) }
            if let token { await searchFence?.finish(token, succeeded: true) }
            return items
        } catch {
            if let token { await searchFence?.finish(token, succeeded: false) }
            throw error
        }
    }

    private func recoverFromLocalMessages(
        accountID: String,
        roomID: String,
        after cursor: Int64,
        head: Int64
    ) async throws -> [ChatDeletionDelta] {
        // 검색 전용 ID도 확인하되 ID/복구 delta를 각각 한 페이지 이상 배열에 쌓지 않는다.
        var afterID: String?
        var recovered: [Int64: ChatDeletionDelta] = [:]
        let end = cursor + min(Int64(pageSize), head - cursor)
        while true {
            try Task.checkCancellation()
            let ids = try await persistence.messageIDs(accountID: accountID, roomID: roomID, afterID: afterID, limit: pageSize)
            if ids.isEmpty { break }
            let deltas = try await repository.deltas(roomID: roomID, messageIDs: ids)
            for delta in deltas where delta.revision > cursor && delta.revision <= end {
                guard delta.roomID == roomID, ids.contains(delta.messageID) else {
                    throw ChatDeletionSyncError.revisionGap(expected: cursor + 1, actual: delta.revision)
                }
                if let previous = recovered[delta.revision], previous.messageID != delta.messageID {
                    throw ChatDeletionSyncError.revisionGap(expected: cursor + 1, actual: delta.revision)
                }
                recovered[delta.revision] = delta
            }
            afterID = ids.last
            if ids.count < pageSize { break }
        }
        return contiguousPrefix(Array(recovered.values), after: cursor)
    }

    private func contiguousPrefix(_ deltas: [ChatDeletionDelta], after cursor: Int64) -> [ChatDeletionDelta] {
        var expected = cursor + 1
        var result: [ChatDeletionDelta] = []
        for delta in deltas.sorted(by: { $0.revision < $1.revision }) {
            if delta.revision < expected { continue }
            guard delta.revision == expected else { break }
            result.append(delta)
            expected += 1
        }
        return result
    }

    private func clean(_ items: [ChatDeletionCleanupItem]) async {
        for item in items where !cleanupPending.contains(item) { cleanupPending.append(item) }
        guard cleanupTask == nil, !cleanupPending.isEmpty else { return }
        cleanupTask = Task { await self.drainCleanup() }
    }

    private func drainCleanup() async {
        defer { cleanupTask = nil }
        while !cleanupPending.isEmpty {
            let item = cleanupPending.removeFirst()
            do {
                try await mediaCleaner.clean(item)
                try await persistence.completeCleanup(item)
            } catch {
                // durable queue를 남겨 다음 앱 실행·동기화에서 재시도한다.
            }
        }
    }

    private func sharedReplyDeltas(accountID: String, roomID: String, messageIDs: [String]) async throws -> [ChatDeletionDelta] {
        let key = ReplyKey(accountID: accountID, roomID: roomID, ids: messageIDs.sorted())
        if let task = replyQueries[key] { return try await task.1.value }
        let id = UUID()
        let task = Task { try await self.repository.deltas(roomID: roomID, messageIDs: key.ids) }
        replyQueries[key] = (id, task)
        defer { if replyQueries[key]?.0 == id { replyQueries.removeValue(forKey: key) } }
        return try await task.value
    }
}
