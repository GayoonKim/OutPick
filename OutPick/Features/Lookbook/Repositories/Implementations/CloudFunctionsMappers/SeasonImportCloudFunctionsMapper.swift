import Foundation

enum SeasonImportCloudFunctionsMapper {
    static func queueReceipt(_ dictionary: [String: Any]) throws -> LookbookImportQueueReceipt {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        guard let state = LookbookImportQueueContract.BatchState(rawValue: try decoder.string("receiptState")),
              let contractVersion = decoder.optionalInt("contractVersion"),
              let stateRevision = decoder.optionalInt("stateRevision") else {
            throw CloudFunctionsClientError.invalidResponse
        }
        let items = try decoder.dictionaries("items").map { item -> LookbookImportQueueReceipt.Item in
            let itemDecoder = CloudFunctionResponseDecoder(dictionary: item)
            let admissionStatus = try itemDecoder.string("admissionStatus")
            guard ["pending", "created", "duplicate", "failed", "skipped"].contains(admissionStatus) else {
                throw CloudFunctionsClientError.invalidResponse
            }
            return LookbookImportQueueReceipt.Item(
                itemID: try itemDecoder.string("itemID"),
                targetID: try itemDecoder.string("targetID"),
                ordinal: try itemDecoder.int("ordinal"),
                admissionStatus: admissionStatus,
                processingStatus: itemDecoder.optionalString("processingStatus"),
                jobID: itemDecoder.optionalString("jobID"),
                executionID: itemDecoder.optionalString("executionID"),
                errorCode: itemDecoder.optionalString("errorCode")
            )
        }
        return LookbookImportQueueReceipt(
            contractVersion: contractVersion,
            requestID: try decoder.string("requestID"),
            batchID: try decoder.string("batchID"),
            brandID: try decoder.string("brandID"),
            kind: try decoder.string("kind"),
            state: state,
            stateRevision: Int64(stateRevision),
            items: items
        )
    }

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
