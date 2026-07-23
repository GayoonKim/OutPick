import Foundation

enum LookbookExtractionReviewCloudFunctionsMapper {
    static func review(_ dictionary: [String: Any]) throws -> LookbookExtractionReview {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        let status = try enumValue(
            SeasonImportJobStatus.self,
            rawValue: try decoder.string("status"),
            field: "status"
        )
        let reviewStatus = try enumValue(
            SeasonImportReviewStatus.self,
            rawValue: try decoder.string("reviewStatus"),
            field: "reviewStatus"
        )
        let candidates = try decoder.dictionaries("candidates").map { item in
            let itemDecoder = CloudFunctionResponseDecoder(dictionary: item)
            guard let url = URL(string: try itemDecoder.string("sourceURL")) else {
                throw CloudFunctionsClientError.invalidResponse
            }
            return LookbookExtractionReviewCandidate(
                candidateKey: try itemDecoder.string("candidateKey"),
                sourceURL: url,
                alt: itemDecoder.optionalString("alt")
            )
        }
        let evidence = dictionary["expectedCountEvidence"] as? [[String: Any]] ?? []
        let expectedCounts = evidence.compactMap {
            CloudFunctionResponseDecoder(dictionary: $0).optionalInt("value")
        }
        return LookbookExtractionReview(
            jobID: try decoder.string("jobID"),
            brandID: BrandID(value: try decoder.string("brandID")),
            status: status,
            reviewStatus: reviewStatus,
            reviewGeneration: try decoder.int("reviewGeneration"),
            reviewSnapshotHash: try decoder.string("reviewSnapshotHash"),
            qualityReasons: decoder.stringArray("qualityReasons"),
            expectedCandidateCounts: expectedCounts,
            candidates: candidates,
            canReanalyze: try decoder.bool("canReanalyze")
        )
    }

    static func receipt(
        _ dictionary: [String: Any]
    ) throws -> LookbookExtractionReviewReceipt {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        return LookbookExtractionReviewReceipt(
            status: try decoder.string("status"),
            duplicate: decoder.optionalBool("duplicate") ?? false
        )
    }

    private static func enumValue<Value: RawRepresentable>(
        _ type: Value.Type,
        rawValue: String,
        field: String
    ) throws -> Value where Value.RawValue == String {
        guard let value = Value(rawValue: rawValue) else {
            throw CloudFunctionsClientError.missingField(field)
        }
        return value
    }
}
