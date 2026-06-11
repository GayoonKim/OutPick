import Foundation

struct SeasonAssetRetryReceipt: Equatable {
    let sourceImportJobID: String
    let seasonID: String
    let status: String
    let isDuplicate: Bool
}
