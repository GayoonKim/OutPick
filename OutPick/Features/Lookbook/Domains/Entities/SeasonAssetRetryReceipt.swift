import Foundation

struct SeasonAssetRetryReceipt: Equatable {
    let sourceImportJobID: String
    let seasonID: String?
    let status: String
    let isDuplicate: Bool
    let requestID: String?
    let batchID: String?

    init(
        sourceImportJobID: String,
        seasonID: String?,
        status: String,
        isDuplicate: Bool,
        requestID: String? = nil,
        batchID: String? = nil
    ) {
        self.sourceImportJobID = sourceImportJobID
        self.seasonID = seasonID
        self.status = status
        self.isDuplicate = isDuplicate
        self.requestID = requestID
        self.batchID = batchID
    }
}
