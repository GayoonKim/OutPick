import Foundation
import GRDB

struct LookbookImportRequestRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "lookbookImportRequest"

    let ownerUID: String
    let requestID: String
    let contractVersion: Int
    let brandID: String?
    let kind: String
    let inputJSON: String
    let payloadDigest: String
    let localState: String
    let batchID: String?
    let receiptJSON: String?
    let stateRevision: Int64?
    let createdAt: Int64
    let updatedAt: Int64
    let settledAt: Int64?
    let expiresAt: Int64?

    init(_ request: LookbookImportRequest) {
        ownerUID = request.ownerUID
        requestID = request.requestID
        contractVersion = request.contractVersion
        brandID = request.brandID
        kind = request.kind
        inputJSON = request.inputJSON
        payloadDigest = request.payloadDigest
        localState = request.localState.rawValue
        batchID = request.batchID
        receiptJSON = request.receiptJSON
        stateRevision = request.stateRevision
        createdAt = request.createdAt
        updatedAt = request.updatedAt
        settledAt = request.settledAt
        expiresAt = request.expiresAt
    }

    var domain: LookbookImportRequest? {
        guard let localState = LookbookImportRequest.LocalState(rawValue: localState) else { return nil }
        return LookbookImportRequest(
            ownerUID: ownerUID,
            requestID: requestID,
            contractVersion: contractVersion,
            brandID: brandID,
            kind: kind,
            inputJSON: inputJSON,
            payloadDigest: payloadDigest,
            localState: localState,
            batchID: batchID,
            receiptJSON: receiptJSON,
            stateRevision: stateRevision,
            createdAt: createdAt,
            updatedAt: updatedAt,
            settledAt: settledAt,
            expiresAt: expiresAt
        )
    }
}
