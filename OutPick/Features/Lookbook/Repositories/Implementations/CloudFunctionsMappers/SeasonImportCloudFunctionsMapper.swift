import Foundation

enum SeasonImportCloudFunctionsMapper {
    static func requestReceipt(
        _ dictionary: [String: Any]
    ) throws -> SeasonImportRequestReceipt {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        return SeasonImportRequestReceipt(
            jobID: try decoder.string("jobID"),
            status: try decoder.string("status"),
            normalizedSeasonURL: try decoder.string("seasonURL"),
            sourceCandidateID: decoder.optionalString("sourceCandidateID"),
            isDuplicate: decoder.optionalBool("duplicate") ?? false
        )
    }

    static func assetRetryReceipt(
        _ dictionary: [String: Any]
    ) throws -> SeasonAssetRetryReceipt {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        return SeasonAssetRetryReceipt(
            sourceImportJobID: try decoder.string("sourceImportJobID"),
            seasonID: try decoder.string("seasonID"),
            status: try decoder.string("status"),
            isDuplicate: decoder.optionalBool("duplicate") ?? false
        )
    }

    static func batchRequestResult(
        _ dictionary: [String: Any]
    ) throws -> SeasonImportBatchRequestResult {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        let jobIDs = decoder.stringArray("jobIDs")
        return SeasonImportBatchRequestResult(
            brandID: BrandID(value: try decoder.string("brandID")),
            candidateIDs: decoder.stringArray("candidateIDs"),
            jobIDs: jobIDs,
            requestedJobCount: try decoder.int("requestedJobCount"),
            requestedImportJobCount: decoder.optionalInt("requestedImportJobCount") ?? jobIDs.count,
            createdJobCount: decoder.optionalInt("createdJobCount") ?? 0,
            duplicateJobCount: decoder.optionalInt("duplicateJobCount") ?? 0,
            failedJobCount: try decoder.int("failedJobCount"),
            skippedJobCount: try decoder.int("skippedJobCount"),
            failedCandidates: failures(dictionary)
        )
    }

    private static func failures(
        _ dictionary: [String: Any]
    ) -> [SeasonImportBatchFailure] {
        guard let items = dictionary["failedCandidates"] as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item in
            let decoder = CloudFunctionResponseDecoder(dictionary: item)
            guard let candidateID = decoder.optionalString("candidateID") else {
                return nil
            }
            return SeasonImportBatchFailure(
                candidateID: candidateID,
                title: decoder.optionalString("title"),
                errorMessage: decoder.optionalString("errorMessage")
                    ?? "시즌 가져오기 작업을 준비하지 못했습니다."
            )
        }
    }
}
