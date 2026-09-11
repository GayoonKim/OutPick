import Foundation

/// 실제 행의 누락만 복구한다. 화면 수명과 캐시 저장은 소비자가 담당한다.
actor ChatMessagePageLoader {
    typealias Fetch = @Sendable (String, ChatMessageSequenceRange) async throws -> [ChatMessage]
    private let local: Fetch
    private let remote: Fetch
    private var tasks: [ChatMessagePageRequest: (UUID, Task<ChatMessagePageResult, Error>)] = [:]
    private struct PageKey: Hashable { let roomID: String; let direction: ChatMessagePageDirection }
    private var partialPages: [PageKey: (ChatMessagePageRequest, [ChatMessage])] = [:]

    init(local: @escaping Fetch, remote: @escaping Fetch) {
        self.local = local
        self.remote = remote
    }

    func load(_ request: ChatMessagePageRequest) async throws -> ChatMessagePageResult {
        if let existing = tasks[request] { return try await existing.1.value }
        let id = UUID()
        let key = PageKey(roomID: request.roomID, direction: request.direction)
        let retained = partialPages[key]?.0 == request ? partialPages[key]!.1 : []
        partialPages.removeValue(forKey: key)
        let local = self.local
        let remote = self.remote
        let task = Task<ChatMessagePageResult, Error> {
            guard let range = request.range else {
                return try ChatMessageCacheGapPolicy.result(for: request, messages: [])
            }
            // 로컬 읽기 실패도 복구 가능한 cache miss로 취급한다.
            let rows = (try? await local(request.roomID, range)) ?? []
            let cached = (try? ChatMessageMergePolicy.merge(retained + rows, roomID: request.roomID)) ?? rows
            let ranges = ChatMessageCacheGapPolicy.recoveryRanges(for: request, messages: cached)
            var fetched: [ChatMessage] = []
            await withTaskGroup(of: [ChatMessage].self) { group in
                // 정책상 최대 두 범위만 생성되므로 무제한 병렬 요청이 없다.
                for missing in ranges {
                    group.addTask {
                        guard let messages = try? await remote(request.roomID, missing),
                              messages.allSatisfy({ $0.roomID == request.roomID && missing.contains($0.seq) }) else {
                            return []
                        }
                        return messages
                    }
                }
                for await messages in group { fetched.append(contentsOf: messages) }
            }
            do {
                return try ChatMessageCacheGapPolicy.result(for: request, messages: cached + fetched)
            } catch ChatMessagePageError.identityConflict {
                // 로컬의 ID/seq 충돌은 원본 범위를 서버에서 다시 확인한다.
                let authoritative = try await remote(request.roomID, range)
                guard authoritative.allSatisfy({ $0.roomID == request.roomID && range.contains($0.seq) }) else {
                    throw ChatMessagePageError.invalidPayload
                }
                var result = try ChatMessageCacheGapPolicy.result(for: request, messages: authoritative)
                result.replacedMessageIDs = Set(cached.filter { old in
                    authoritative.contains { fresh in
                        (fresh.seq == old.seq && fresh.ID != old.ID) || (fresh.ID == old.ID && fresh.seq != old.seq)
                    }
                }.map(\.ID))
                return result
            }
        }
        tasks[request] = (id, task)
        defer { if tasks[request]?.0 == id { tasks.removeValue(forKey: request) } }
        let result = try await task.value
        if !result.isComplete { partialPages[key] = (request, result.messages) }
        return result
    }

    func cancelAll() {
        for (_, task) in tasks.values { task.cancel() }
        tasks.removeAll()
        partialPages.removeAll()
    }
}
