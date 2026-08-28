import Foundation

protocol ChatDeletionMediaCleaning {
    func clean(_ item: ChatDeletionCleanupItem) async throws
}

final class DefaultChatDeletionMediaCleaner: ChatDeletionMediaCleaning {
    private let imageLoader: ChatAttachmentImageLoading
    private let videoDiskCache: ChatVideoDiskCaching
    private let storageURLResolver: ChatStorageURLResolving
    private let fileManager: FileManager

    init(
        imageLoader: ChatAttachmentImageLoading,
        videoDiskCache: ChatVideoDiskCaching,
        storageURLResolver: ChatStorageURLResolving,
        fileManager: FileManager = .default
    ) {
        self.imageLoader = imageLoader
        self.videoDiskCache = videoDiskCache
        self.storageURLResolver = storageURLResolver
        self.fileManager = fileManager
    }

    func clean(_ item: ChatDeletionCleanupItem) async throws {
        switch item.kind {
        case .image:
            await imageLoader.removeCachedImage(for: item.path)
            await storageURLResolver.removeCachedURL(for: item.path)
        case .video:
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

    init(
        repository: ChatDeletionSyncRepositoryProtocol,
        persistence: ChatDeletionSyncPersisting,
        mediaCleaner: ChatDeletionMediaCleaning,
        pageSize: Int = 100
    ) {
        self.repository = repository
        self.persistence = persistence
        self.mediaCleaner = mediaCleaner
        self.pageSize = max(1, min(pageSize, 100))
    }

    func reconcile(
        roomID: String,
        accountID: String,
        allowEmptyLocalBootstrap: Bool
    ) async throws -> Set<String> {
        let head = try await repository.headRevision(roomID: roomID)
        guard head >= 0 else { throw ChatDeletionSyncError.invalidHead }
        var cursor = try await persistence.cursor(accountID: accountID, roomID: roomID)
        guard head > cursor else {
            await resumePendingCleanup()
            return []
        }

        if cursor == 0,
           allowEmptyLocalBootstrap,
           !(try await persistence.hasServerMessages(roomID: roomID)) {
            try await persistence.bootstrapCursor(head, accountID: accountID, roomID: roomID)
            await resumePendingCleanup()
            return []
        }

        var applied = Set<String>()
        while cursor < head {
            let page = try await repository.deltas(
                roomID: roomID,
                afterRevision: cursor,
                limit: pageSize
            ).filter { $0.revision <= head }

            let usable: [ChatDeletionDelta]
            if page.first?.revision == cursor + 1 {
                usable = contiguousPrefix(page, after: cursor)
            } else {
                usable = try await recoverFromLocalMessages(roomID: roomID, after: cursor, head: head)
            }
            guard !usable.isEmpty else {
                throw ChatDeletionSyncError.revisionGap(expected: cursor + 1, actual: page.first?.revision)
            }

            let cleanup = try await persistence.apply(
                usable,
                accountID: accountID,
                roomID: roomID
            )
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
        let cursor = try await persistence.cursor(accountID: accountID, roomID: event.roomID)
        switch event.kind {
        case .message(let delta) where delta.revision == cursor + 1:
            let cleanup = try await persistence.apply(
                [delta],
                accountID: accountID,
                roomID: event.roomID
            )
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
            resolvedDeleted.append(contentsOf: try await repository.deltas(
                roomID: roomID,
                messageIDs: Array(unknownReplyTargetIDs)
            ))
        }

        if !resolvedDeleted.isEmpty {
            let unique = Dictionary(
                resolvedDeleted.map { ($0.messageID, $0) },
                uniquingKeysWith: { lhs, rhs in lhs.revision >= rhs.revision ? lhs : rhs }
            ).values.map { $0 }
            let cleanup = try await persistence.recordResolvedDeletions(
                unique,
                accountID: accountID,
                roomID: roomID
            )
            await clean(cleanup)
        }
        return try await persistence.sanitize(
            messages,
            accountID: accountID,
            roomID: roomID
        )
    }

    private func recoverFromLocalMessages(
        roomID: String,
        after cursor: Int64,
        head: Int64
    ) async throws -> [ChatDeletionDelta] {
        let ids = try await persistence.messageIDs(roomID: roomID)
        let deltas = try await repository.deltas(roomID: roomID, messageIDs: ids)
            .filter { $0.revision > cursor && $0.revision <= head }
            .sorted { $0.revision < $1.revision }
        return contiguousPrefix(deltas, after: cursor)
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
        for item in items {
            do {
                try await mediaCleaner.clean(item)
                try await persistence.completeCleanup(item)
            } catch {
                // durable queue를 남겨 다음 앱 실행·동기화에서 재시도한다.
            }
        }
    }
}
