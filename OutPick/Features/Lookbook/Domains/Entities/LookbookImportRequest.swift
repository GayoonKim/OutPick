import Foundation

struct LookbookImportRequest: Equatable {
    enum LocalState: String, Codable, CaseIterable {
        case prepared
        case submitting
        case accepted
        case needsReconcile
        case settled
    }

    let ownerUID: String
    let requestID: String
    let contractVersion: Int
    var brandID: String?
    let kind: String
    let inputJSON: String
    let payloadDigest: String
    var localState: LocalState
    var batchID: String?
    var receiptJSON: String?
    var stateRevision: Int64?
    let createdAt: Int64
    var updatedAt: Int64
    var settledAt: Int64?
    var expiresAt: Int64?
}
