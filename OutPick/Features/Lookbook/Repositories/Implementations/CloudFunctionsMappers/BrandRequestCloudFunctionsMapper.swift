import Foundation

enum BrandRequestCloudFunctionsMapper {
    static func request(_ dictionary: [String: Any]) throws -> BrandRequest {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        return BrandRequest(
            id: try decoder.string("requestID"),
            brandName: try decoder.string("brandName"),
            normalizedBrandName: decoder.optionalString("normalizedBrandName") ?? "",
            englishBrandName: decoder.optionalString("englishBrandName"),
            normalizedEnglishBrandName: decoder.optionalString("normalizedEnglishBrandName"),
            groupID: decoder.optionalString("groupID"),
            dedupeKey: decoder.optionalString("dedupeKey"),
            dedupeKeySource: decoder.optionalString("dedupeKeySource"),
            status: BrandRequestStatus(rawValue: try decoder.string("status")) ?? .submitted,
            resolvedBrandID: decoder.optionalString("resolvedBrandID").map(BrandID.init(value:)),
            rejectionReason: decoder.optionalString("rejectionReason"),
            createdAt: decoder.optionalDate("createdAt"),
            updatedAt: decoder.optionalDate("updatedAt")
        )
    }

    static func group(_ dictionary: [String: Any]) throws -> AdminBrandRequestGroup {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        return AdminBrandRequestGroup(
            id: try decoder.string("groupID"),
            dedupeKey: decoder.optionalString("dedupeKey") ?? "",
            dedupeKeySource: decoder.optionalString("dedupeKeySource") ?? "",
            displayNameSnapshot: try decoder.string("displayNameSnapshot"),
            normalizedBrandName: decoder.optionalString("normalizedBrandName") ?? "",
            englishBrandName: decoder.optionalString("englishBrandName"),
            normalizedEnglishBrandName: decoder.optionalString("normalizedEnglishBrandName"),
            requestCount: decoder.optionalInt("requestCount") ?? 0,
            adminStage: BrandRequestAdminStage(
                rawValue: try decoder.string("adminStage")
            ) ?? .requested,
            status: BrandRequestStatus(rawValue: try decoder.string("status")) ?? .submitted,
            rejectionReason: decoder.optionalString("rejectionReason")
                .flatMap(BrandRequestRejectionReason.init(rawValue:)),
            resolvedBrandID: decoder.optionalString("resolvedBrandID").map(BrandID.init(value:)),
            createdBrandID: decoder.optionalString("createdBrandID").map(BrandID.init(value:)),
            brandCreatedAt: decoder.optionalDate("brandCreatedAt"),
            brandCreatedBy: decoder.optionalString("brandCreatedBy"),
            adminNote: decoder.optionalString("adminNote"),
            lastRequestID: decoder.optionalString("lastRequestID"),
            lastRequestedAt: decoder.optionalDate("lastRequestedAt"),
            createdAt: decoder.optionalDate("createdAt"),
            updatedAt: decoder.optionalDate("updatedAt"),
            reviewedAt: decoder.optionalDate("reviewedAt"),
            resolvedAt: decoder.optionalDate("resolvedAt"),
            rejectedAt: decoder.optionalDate("rejectedAt")
        )
    }

    static func stageReceipt(
        _ dictionary: [String: Any],
        fallbackStatus: BrandRequestStatus,
        fallbackStage: BrandRequestAdminStage
    ) throws -> AdminBrandRequestGroupStageUpdateReceipt {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        return AdminBrandRequestGroupStageUpdateReceipt(
            groupID: try decoder.string("groupID"),
            status: BrandRequestStatus(rawValue: try decoder.string("status")) ?? fallbackStatus,
            adminStage: BrandRequestAdminStage(
                rawValue: try decoder.string("adminStage")
            ) ?? fallbackStage,
            updatedRequestCount: decoder.optionalInt("updatedRequestCount") ?? 0
        )
    }
}
