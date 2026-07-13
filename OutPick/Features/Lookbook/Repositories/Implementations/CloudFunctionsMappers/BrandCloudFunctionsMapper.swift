import Foundation

enum BrandCloudFunctionsMapper {
    static func brand(_ dictionary: [String: Any]) throws -> Brand {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        let metrics = CloudFunctionResponseDecoder(
            dictionary: dictionary["metrics"] as? [String: Any] ?? [:]
        )

        return Brand(
            id: BrandID(value: try decoder.string("brandID")),
            name: try decoder.string("name"),
            englishName: decoder.optionalString("englishName"),
            websiteURL: decoder.optionalString("websiteURL"),
            lookbookArchiveURL: decoder.optionalString("lookbookArchiveURL"),
            logoThumbPath: decoder.optionalString("logoThumbPath"),
            logoDetailPath: decoder.optionalString("logoDetailPath"),
            logoOriginalPath: decoder.optionalString("logoOriginalPath"),
            isFeatured: decoder.optionalBool("isFeatured") ?? false,
            discoveryStatus: BrandDiscoveryStatus(
                rawValue: decoder.optionalString("discoveryStatus") ?? ""
            ) ?? .idle,
            lastDiscoveryErrorMessage: decoder.optionalString("lastDiscoveryErrorMessage"),
            lastDiscoveryRequestedAt: decoder.optionalDate("lastDiscoveryRequestedAt"),
            lastDiscoveryCompletedAt: decoder.optionalDate("lastDiscoveryCompletedAt"),
            metrics: BrandMetrics(
                likeCount: metrics.optionalInt("likeCount") ?? 0,
                viewCount: metrics.optionalInt("viewCount") ?? 0,
                popularScore: metrics.optionalDouble("popularScore") ?? 0
            ),
            deletionStatus: BrandDeletionStatus(
                rawValue: decoder.optionalString("deletionStatus") ?? ""
            ) ?? .active,
            updatedAt: decoder.optionalDate("updatedAt") ?? Date(timeIntervalSince1970: 0)
        )
    }

    static func managerReceipt(
        _ dictionary: [String: Any],
        fallbackRemoved: Bool
    ) throws -> BrandManagerMutationReceipt {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        return BrandManagerMutationReceipt(
            brandID: BrandID(value: try decoder.string("brandID")),
            userID: UserID(value: try decoder.string("uid")),
            email: try decoder.string("email"),
            role: BrandManagerRole(rawValue: try decoder.string("role")) ?? .admin,
            duplicate: decoder.optionalBool("duplicate") ?? false,
            removed: decoder.optionalBool("removed") ?? fallbackRemoved
        )
    }
}
