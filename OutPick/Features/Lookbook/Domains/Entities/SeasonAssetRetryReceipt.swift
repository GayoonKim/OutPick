import Foundation

struct SeasonAssetRetryReceipt: Equatable {
    let jobID: String
    let status: String
    let sourceImportJobID: String
    let isDuplicate: Bool
}
