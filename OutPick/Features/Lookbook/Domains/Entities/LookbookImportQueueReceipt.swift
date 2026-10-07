import Foundation

struct LookbookImportQueueReceipt: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        let itemID: String
        let targetID: String
        let ordinal: Int
        let admissionStatus: String
        let processingStatus: String?
        let jobID: String?
        let executionID: String?
        let errorCode: String?

        var id: String { itemID }
    }

    let contractVersion: Int
    let requestID: String
    let batchID: String
    let brandID: String
    let kind: String
    let state: LookbookImportQueueContract.BatchState
    let stateRevision: Int64
    let items: [Item]

    var isSettled: Bool { state == .released }

    var failedItemIDs: [String] {
        items.filter { $0.admissionStatus == "failed" }
            .map(\.targetID)
    }

    var candidateIDs: [String] { items.map(\.targetID) }

    private func status(_ item: Item) -> String {
        item.processingStatus ?? item.admissionStatus
    }

    var succeededCount: Int { items.filter { ["succeeded", "completed"].contains(status($0)) }.count }
    var reviewRequiredCount: Int { items.filter { status($0) == "awaitingReview" }.count }
    var failedCount: Int { items.filter { ["failed", "partialFailed", "cancelled"].contains(status($0)) }.count }
    var recoveryRequiredCount: Int { items.filter { status($0) == "recoveryRequired" }.count }
    var inProgressCount: Int {
        items.filter { ["pending", "created", "queued", "dispatching", "active", "processing", "draining", "retryWaiting"].contains(status($0)) }.count
    }
}
