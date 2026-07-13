import Foundation

enum LookbookExtractionDiagnosticCloudFunctionsMapper {
    static func diagnostic(
        _ dictionary: [String: Any]
    ) throws -> LookbookExtractionDiagnostic {
        let decoder = CloudFunctionResponseDecoder(dictionary: dictionary)
        let rawType = try decoder.string("type")
        let rawStatus = try decoder.string("status")
        return LookbookExtractionDiagnostic(
            id: try decoder.string("id"),
            brandID: BrandID(value: try decoder.string("brandID")),
            type: LookbookExtractionDiagnosticType(rawValue: rawType) ?? .seasonDiscovery,
            status: LookbookExtractionDiagnosticStatus(rawValue: rawStatus) ?? .failed,
            sourceURL: decoder.optionalString("sourceURL"),
            summaryMessage: decoder.optionalString("summaryMessage"),
            errorMessage: decoder.optionalString("errorMessage"),
            failureReasons: decoder.stringArray("failureReasons")
                .compactMap(LookbookExtractionFailureReason.init(rawValue:)),
            suggestedFixScope: LookbookExtractionSuggestedFixScope(
                rawValue: decoder.optionalString("suggestedFixScope") ?? ""
            ) ?? .unknown,
            suggestedFixes: suggestedFixes(dictionary),
            seasonDiscovery: seasonDiscovery(dictionary),
            seasonImageImport: seasonImageImport(dictionary),
            createdAt: decoder.optionalDate("createdAt"),
            updatedAt: decoder.optionalDate("updatedAt"),
            completedAt: decoder.optionalDate("completedAt"),
            expiresAt: decoder.optionalDate("expiresAt")
        )
    }

    private static func suggestedFixes(
        _ dictionary: [String: Any]
    ) -> [LookbookExtractionSuggestedFix] {
        guard let items = dictionary["suggestedFixes"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            let decoder = CloudFunctionResponseDecoder(dictionary: item)
            guard let type = decoder.optionalString("type") else { return nil }
            return LookbookExtractionSuggestedFix(
                type: type,
                scope: LookbookExtractionSuggestedFixScope(
                    rawValue: decoder.optionalString("scope") ?? ""
                ) ?? .unknown,
                confidence: decoder.optionalDouble("confidence") ?? 0,
                message: decoder.optionalString("message") ?? ""
            )
        }
    }

    private static func seasonDiscovery(
        _ dictionary: [String: Any]
    ) -> SeasonDiscoveryDiagnosticDetail? {
        guard let value = dictionary["seasonDiscovery"] as? [String: Any] else { return nil }
        let decoder = CloudFunctionResponseDecoder(dictionary: value)
        return SeasonDiscoveryDiagnosticDetail(
            staticCandidateCount: decoder.optionalInt("staticCandidateCount") ?? 0,
            renderedCandidateCount: decoder.optionalInt("renderedCandidateCount"),
            candidateCountBeforeExpansion: decoder.optionalInt("candidateCountBeforeExpansion") ?? 0,
            candidateCountAfterExpansion: decoder.optionalInt("candidateCountAfterExpansion") ?? 0,
            storedCandidateCount: decoder.optionalInt("storedCandidateCount") ?? 0,
            diagnosticCandidateCount: decoder.optionalInt("diagnosticCandidateCount") ?? 0,
            loadMoreDetected: decoder.optionalBool("loadMoreDetected") ?? false,
            loadMoreClickCount: decoder.optionalInt("loadMoreClickCount") ?? 0,
            infiniteScrollAttempted: decoder.optionalBool("infiniteScrollAttempted") ?? false,
            scrollAttemptCount: decoder.optionalInt("scrollAttemptCount") ?? 0,
            dynamicRenderingDetected: decoder.optionalBool("dynamicRenderingDetected") ?? false,
            renderedFallbackUsed: decoder.optionalBool("renderedFallbackUsed") ?? false,
            parserStrategy: decoder.optionalString("parserStrategy") ?? "unknown",
            adapterKey: decoder.optionalString("adapterKey")
        )
    }

    private static func seasonImageImport(
        _ dictionary: [String: Any]
    ) -> SeasonImageImportDiagnosticDetail? {
        guard let value = dictionary["seasonImageImport"] as? [String: Any] else { return nil }
        let decoder = CloudFunctionResponseDecoder(dictionary: value)
        return SeasonImageImportDiagnosticDetail(
            sourceImportJobID: decoder.optionalString("sourceImportJobID") ?? "",
            targetSeasonID: decoder.optionalString("targetSeasonID"),
            seasonTitle: decoder.optionalString("seasonTitle"),
            expectedImageCount: decoder.optionalInt("expectedImageCount") ?? 0,
            importedImageCount: decoder.optionalInt("importedImageCount") ?? 0,
            failedImageCount: decoder.optionalInt("failedImageCount") ?? 0,
            retryable: decoder.optionalBool("retryable") ?? false
        )
    }
}
