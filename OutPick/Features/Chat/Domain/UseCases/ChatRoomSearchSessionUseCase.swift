import Foundation

/// Phase 5 화면이 사용할 세션 capability. 기존 화면의 전량 계약과 구분한다.
@MainActor final class ChatRoomSearchSessionUseCase: ChatRoomSearchSessionUseCaseProtocol {
    private let manager: any ChatSearchSessionManaging
    init(manager: any ChatSearchSessionManaging) { self.manager = manager }
    var snapshot: ChatSearchSessionSnapshot? { manager.snapshot }
    @discardableResult func observe(_ callback: @escaping @MainActor (ChatSearchSessionSnapshot?) -> Void) -> UUID { manager.observe(callback) }
    func removeObserver(_ id: UUID) { manager.removeObserver(id) }
    func search(roomID: String, keyword: String) { manager.search(roomID: roomID, keyword: keyword) }
    func continueSearch(session: ChatSearchSessionIdentity) { manager.continueSearch(session: session) }
    func prefetchIfNeeded(session: ChatSearchSessionIdentity) { manager.prefetchIfNeeded(session: session) }
    func prepareNavigation(session: ChatSearchSessionIdentity, direction: ChatSearchDirection) async throws -> ChatSearchPendingNavigation? {
        try await manager.prepareNavigation(session: session, direction: direction)
    }
    func commitNavigation(_ navigation: ChatSearchPendingNavigation) async throws { try await manager.commitNavigation(navigation) }
    func cancel(session: ChatSearchSessionIdentity) async { await manager.cancel(session: session) }
    func retry() { manager.retry() }
    func setForeground(_ foreground: Bool) { manager.setForeground(foreground) }
    func stop() { manager.stop() }
}
