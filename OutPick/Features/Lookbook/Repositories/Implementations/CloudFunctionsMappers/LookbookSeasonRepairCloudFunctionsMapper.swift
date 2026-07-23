import Foundation

enum LookbookSeasonRepairCloudFunctionsMapper {
    static func preview(
        _ dictionary: [String: Any]
    ) throws -> LookbookSeasonRepairPreview {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        return LookbookSeasonRepairPreview(
            jobID: try decoder.string("jobID"),
            brandID: BrandID(value: try decoder.string("brandID")),
            seasonID: SeasonID(value: try decoder.string("seasonID")),
            generation: try decoder.int("repairGeneration"),
            snapshotHash: try decoder.string("repairSnapshotHash"),
            keep: try existingEntries(decoder.dictionaries("keep")),
            add: try addEntries(decoder.dictionaries("add")),
            reorder: try existingEntries(decoder.dictionaries("reorder")),
            removeCandidates: try existingEntries(
                decoder.dictionaries("removeCandidates")
            ),
            resultingPostCount: try decoder.int("resultingPostCount")
        )
    }

    static func receipt(
        _ dictionary: [String: Any]
    ) throws -> LookbookSeasonRepairReceipt {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        guard
            let status = SeasonRepairStatus(rawValue: try decoder.string("status"))
        else {
            throw CloudFunctionsClientError.missingField("status")
        }
        return LookbookSeasonRepairReceipt(
            jobID: try decoder.string("jobID"),
            seasonID: SeasonID(value: try decoder.string("seasonID")),
            generation: try decoder.int("repairGeneration"),
            status: status,
            duplicate: decoder.optionalBool("duplicate") ?? false
        )
    }

    private static func existingEntries(
        _ dictionaries: [[String: Any]]
    ) throws -> [LookbookSeasonRepairExistingEntry] {
        try dictionaries.map { dictionary in
            let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
            guard let sourceURL = URL(string: try decoder.string("sourceURL")) else {
                throw CloudFunctionsClientError.invalidResponse
            }
            let matchedBy = decoder.optionalString("matchedBy")
                .flatMap(LookbookSeasonRepairMatch.init(rawValue:))
            return LookbookSeasonRepairExistingEntry(
                postID: try decoder.string("postID"),
                sourceURL: sourceURL,
                previousIndex: try decoder.int("previousIndex"),
                proposedIndex: decoder.optionalInt("proposedIndex"),
                matchedBy: matchedBy
            )
        }
    }

    private static func addEntries(
        _ dictionaries: [[String: Any]]
    ) throws -> [LookbookSeasonRepairAddEntry] {
        try dictionaries.map { dictionary in
            let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
            guard let sourceURL = URL(string: try decoder.string("sourceURL")) else {
                throw CloudFunctionsClientError.invalidResponse
            }
            return LookbookSeasonRepairAddEntry(
                postID: try decoder.string("postID"),
                candidateKey: try decoder.string("candidateKey"),
                sourceURL: sourceURL,
                proposedIndex: try decoder.int("proposedIndex"),
                alt: decoder.optionalString("alt"),
                contentHash: decoder.optionalString("contentHash")
            )
        }
    }
}
