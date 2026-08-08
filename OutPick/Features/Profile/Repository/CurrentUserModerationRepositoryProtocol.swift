protocol CurrentUserModerationRepositoryProtocol {
    func fetchAndBindCurrentState() async throws -> CurrentUserModerationState
}
