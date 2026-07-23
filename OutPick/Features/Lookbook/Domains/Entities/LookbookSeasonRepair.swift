import Foundation

enum LookbookSeasonRepairMatch: String, Equatable {
    case canonicalURL
    case contentHash
}

struct LookbookSeasonRepairExistingEntry: Equatable, Identifiable {
    let postID: String
    let sourceURL: URL
    let previousIndex: Int
    let proposedIndex: Int?
    let matchedBy: LookbookSeasonRepairMatch?

    var id: String { postID }
}

struct LookbookSeasonRepairAddEntry: Equatable, Identifiable {
    let postID: String
    let candidateKey: String
    let sourceURL: URL
    let proposedIndex: Int
    let alt: String?
    let contentHash: String?

    var id: String { postID }
}

struct LookbookSeasonRepairPreview: Equatable {
    let jobID: String
    let brandID: BrandID
    let seasonID: SeasonID
    let generation: Int
    let snapshotHash: String
    let keep: [LookbookSeasonRepairExistingEntry]
    let add: [LookbookSeasonRepairAddEntry]
    let reorder: [LookbookSeasonRepairExistingEntry]
    let removeCandidates: [LookbookSeasonRepairExistingEntry]
    let resultingPostCount: Int

    var hasChanges: Bool {
        !add.isEmpty || !reorder.isEmpty || !removeCandidates.isEmpty
    }
}

struct LookbookSeasonRepairReceipt: Equatable {
    let jobID: String
    let seasonID: SeasonID
    let generation: Int
    let status: SeasonRepairStatus
    let duplicate: Bool
}
