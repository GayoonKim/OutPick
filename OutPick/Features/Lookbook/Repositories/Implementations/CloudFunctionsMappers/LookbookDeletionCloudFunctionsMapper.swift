import Foundation

enum LookbookDeletionCloudFunctionsMapper {
    static func mutationReceipt(
        _ dictionary: [String: Any]
    ) throws -> LookbookDeletionMutationReceipt {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        return LookbookDeletionMutationReceipt(
            brandID: BrandID(value: try decoder.string("brandID")),
            seasonID: decoder.optionalString("seasonID").map(SeasonID.init(value:)),
            postID: decoder.optionalString("postID").map(PostID.init(value:)),
            requestID: decoder.optionalString("requestID"),
            status: decoder.optionalString("status") ?? "",
            duplicate: decoder.optionalBool("duplicate") ?? false,
            cancelled: decoder.optionalBool("cancelled") ?? false,
            restored: decoder.optionalBool("restored") ?? false
        )
    }

    static func batchResult(
        _ dictionary: [String: Any]
    ) throws -> LookbookDeletionBatchResult {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        return LookbookDeletionBatchResult(
            brandID: BrandID(value: try decoder.string("brandID")),
            targetType: LookbookDeletionTargetType(rawValue: try decoder.string("targetType")) ?? .post,
            requestedCount: try decoder.int("requestedCount"),
            succeededCount: try decoder.int("succeededCount"),
            failedCount: try decoder.int("failedCount"),
            results: try decoder.dictionaries("results").map(batchItem)
        )
    }

    static func requestPage(
        _ dictionary: [String: Any]
    ) throws -> LookbookDeletionRequestPage {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        let nextCursor: LookbookDeletionRequestPage.Cursor?
        if let value = dictionary["nextCursor"] as? [String: Any] {
            let cursorDecoder = CloudFunctionResponseDecoder(dictionary: value)
            if let updatedAt = cursorDecoder.optionalString("updatedAt"),
               let requestID = cursorDecoder.optionalString("requestID") {
                nextCursor = .init(updatedAt: updatedAt, requestID: requestID)
            } else {
                nextCursor = nil
            }
        } else {
            nextCursor = nil
        }
        return LookbookDeletionRequestPage(
            requests: try decoder.dictionaries("requests").map(request),
            nextCursor: nextCursor
        )
    }

    static func retryReceipt(
        _ dictionary: [String: Any]
    ) throws -> LookbookDeletionRetryReceipt {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        guard let state = LookbookDeletionManualRetryState(
            rawValue: try decoder.string("manualRetryState")
        ) else {
            throw CloudFunctionsClientError.invalidResponse
        }
        return LookbookDeletionRetryReceipt(
            requestID: try decoder.string("requestID"),
            manualRetryState: state,
            duplicate: try decoder.bool("duplicate")
        )
    }

    private static func batchItem(
        _ dictionary: [String: Any]
    ) throws -> LookbookDeletionBatchItemResult {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        return LookbookDeletionBatchItemResult(
            success: decoder.optionalBool("success") ?? false,
            targetType: LookbookDeletionTargetType(rawValue: try decoder.string("targetType")) ?? .post,
            targetID: try decoder.string("targetID"),
            brandID: BrandID(value: try decoder.string("brandID")),
            seasonID: decoder.optionalString("seasonID").map(SeasonID.init(value:)),
            postID: decoder.optionalString("postID").map(PostID.init(value:)),
            requestID: decoder.optionalString("requestID"),
            status: decoder.optionalString("status"),
            duplicate: decoder.optionalBool("duplicate") ?? false,
            code: decoder.optionalString("code"),
            message: decoder.optionalString("message")
        )
    }

    private static func request(
        _ dictionary: [String: Any]
    ) throws -> LookbookDeletionRequest {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        return LookbookDeletionRequest(
            requestID: try decoder.string("requestID"),
            targetType: LookbookDeletionTargetType(rawValue: try decoder.string("targetType")) ?? .brand,
            targetID: try decoder.string("targetID"),
            targetPath: try decoder.string("targetPath"),
            brandID: BrandID(value: try decoder.string("brandID")),
            seasonID: decoder.optionalString("seasonID").map(SeasonID.init(value:)),
            postID: decoder.optionalString("postID").map(PostID.init(value:)),
            status: LookbookDeletionRequestStatus(rawValue: try decoder.string("status")) ?? .active,
            requestedBy: UserID(value: decoder.optionalString("requestedBy") ?? ""),
            requestedAt: decoder.optionalDate("requestedAt"),
            restoreUntil: decoder.optionalDate("restoreUntil"),
            purgeAfter: decoder.optionalDate("purgeAfter"),
            reason: decoder.optionalString("reason"),
            cancelledBy: decoder.optionalString("cancelledBy").map(UserID.init(value:)),
            cancelledAt: decoder.optionalDate("cancelledAt"),
            restoredBy: decoder.optionalString("restoredBy").map(UserID.init(value:)),
            restoredAt: decoder.optionalDate("restoredAt"),
            updatedBy: decoder.optionalString("updatedBy").map(UserID.init(value:)),
            updatedAt: decoder.optionalDate("updatedAt"),
            targetDisplayName: decoder.optionalString("targetDisplayName"),
            targetImagePath: decoder.optionalString("targetImagePath"),
            brandName: decoder.optionalString("brandName"),
            brandEnglishName: decoder.optionalString("brandEnglishName"),
            brandLogoThumbPath: decoder.optionalString("brandLogoThumbPath"),
            seasonTitle: decoder.optionalString("seasonTitle"),
            seasonCoverThumbPath: decoder.optionalString("seasonCoverThumbPath"),
            postCaption: decoder.optionalString("postCaption"),
            postImageThumbPath: decoder.optionalString("postImageThumbPath"),
            autoRetryEligible: decoder.optionalBool("autoRetryEligible") ?? false,
            retryAfter: decoder.optionalDate("retryAfter"),
            purgeAttemptCount: decoder.optionalInt("purgeAttemptCount") ?? 0,
            purgeErrorMessage: decoder.optionalString("purgeErrorMessage"),
            manualRetryState: decoder.optionalString("manualRetryState")
                .flatMap(LookbookDeletionManualRetryState.init(rawValue:)),
            manualRetryCount: decoder.optionalInt("manualRetryCount") ?? 0,
            purgeInProgress: decoder.optionalBool("purgeInProgress") ?? false
        )
    }
}
