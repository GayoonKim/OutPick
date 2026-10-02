import Foundation

@MainActor final class ChatSearchNavigator {
    private weak var owner: ChatSearchSessionController?
    private var generation: UInt64 = 0
    init(owner: ChatSearchSessionController) { self.owner = owner }
    func invalidate() { generation &+= 1 }

    func prepare(session: ChatSearchSessionIdentity, direction: ChatSearchDirection) async throws -> ChatSearchPendingNavigation? {
        guard let owner, let run = owner.active, run.identity == session else { return nil }
        invalidate(); run.wake()
        let request = generation
        while owner.valid(run), run.identity == session, request == generation, owner.foreground, run.failure == nil {
            guard !Task.isCancelled else { throw CancellationError() }
            if !run.created || owner.snapshot?.isRefreshing == true {
                await withCheckedContinuation { run.waiters.append($0) }; continue
            }
            let resultRevision = run.resultRevision
            if let anchor = run.replacementAnchor {
                var result = try await owner.store.neighbor(identity: session, anchor: anchor, direction: .older)
                if result == nil { result = try await owner.store.neighbor(identity: session, anchor: anchor, direction: .newer) }
                guard owner.valid(run), request == generation, owner.snapshot?.isRefreshing == false, owner.foreground else { return nil }
                if resultRevision != run.resultRevision { continue }
                if let result {
                    return ChatSearchPendingNavigation(identity: session, navigationGeneration: request, visibilityRevision: run.visibility.revision, target: result)
                }
                if run.exhausted || run.pagesRemaining == 0 { return nil }
                await withCheckedContinuation { run.waiters.append($0) }; continue
            }
            var offset = 0
            if let selected = run.selected, let ordinal = try await owner.store.ordinal(identity: session, messageID: selected.messageID) {
                offset = direction == .older ? ordinal : max(0, ordinal - 2)
                if direction == .newer && ordinal == 1 { return nil }
            } else if let preferred = run.preferredID {
                if let ordinal = try await owner.store.ordinal(identity: session, messageID: preferred) { offset = ordinal - 1 }
            }
            let result = try await owner.store.results(identity: session, offset: offset, limit: 1).first
            guard owner.valid(run), run.identity == session, request == generation, owner.foreground,
                  owner.snapshot?.isRefreshing == false else { return nil }
            if resultRevision != run.resultRevision { continue }
            if let result {
                return ChatSearchPendingNavigation(identity: session, navigationGeneration: request,
                    visibilityRevision: run.visibility.revision, target: result)
            }
            if run.exhausted || run.pagesRemaining == 0 { return nil }
            await withCheckedContinuation { run.waiters.append($0) }
        }
        return nil
    }

    func commit(_ pending: ChatSearchPendingNavigation) async throws {
        guard let owner, let run = owner.active else { throw CancellationError() }
        let matches = {
            owner.valid(run) && run.identity == pending.identity && owner.foreground && run.failure == nil
                && self.generation == pending.navigationGeneration && run.visibility.revision == pending.visibilityRevision
                && owner.snapshot?.isRefreshing == false
        }
        guard matches(), try await owner.store.ordinal(identity: pending.identity, messageID: pending.target.messageID) != nil,
              matches() else { throw CancellationError() }
        run.selected = pending.target; run.preferredID = nil; run.replacementAnchor = nil
        _ = try await owner.publish(run)
    }
}
