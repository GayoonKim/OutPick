import Foundation

protocol CurrentUserAccountRepositoryProtocol {
    func fetchAccount(userID: String) async throws -> UserAccount?
}
