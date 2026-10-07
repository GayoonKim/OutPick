import Foundation

protocol LookbookImportRequestStoringRepositoryProtocol {
    func prepareOrReuse(_ request: LookbookImportRequest) async throws -> (request: LookbookImportRequest, didReuse: Bool)
    func update(_ request: LookbookImportRequest) async throws
    func fetchUnsettled(ownerUID: String, brandID: String?) async throws -> [LookbookImportRequest]
    func deleteExpiredSettled(now: Int64, limit: Int) async throws -> Int
}

struct UnavailableLookbookImportRequestStore: LookbookImportRequestStoringRepositoryProtocol {
    func prepareOrReuse(_ request: LookbookImportRequest) async throws -> (request: LookbookImportRequest, didReuse: Bool) {
        throw LookbookImportRequestStoreUnavailable.error
    }

    func update(_ request: LookbookImportRequest) async throws {
        throw LookbookImportRequestStoreUnavailable.error
    }

    func fetchUnsettled(ownerUID: String, brandID: String?) async throws -> [LookbookImportRequest] { [] }
    func deleteExpiredSettled(now: Int64, limit: Int) async throws -> Int { 0 }
}

enum LookbookImportRequestStoreUnavailable {
    static let error = NSError(
        domain: "LookbookImportRequestStore",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "요청 복원 저장소가 준비되지 않았습니다."]
    )
}
