import Foundation
import CoreFoundation
import FirebaseFunctions

enum BrandRequestCloudFunctionsMapper {
    static func status(_ dictionary: [String: Any]) throws -> BrandRequestStatus {
        let value = try CloudFunctionResponseDecoder(dictionary: dictionary).string("status")
        guard let status = BrandRequestStatus(rawValue: value) else {
            throw CloudFunctionsClientError.invalidResponse
        }
        return status
    }

    static func submissionReceipt(_ dictionary: [String: Any]) throws -> BrandRequestSubmissionReceipt {
        let status = try status(dictionary)
        let destination = try nullableBrandID(dictionary)
        guard let duplicate = dictionary["isDuplicate"] as? NSNumber,
              CFGetTypeID(duplicate) == CFBooleanGetTypeID(),
              let remaining = dictionary["remainingToday"] as? NSNumber,
              CFGetTypeID(remaining) != CFBooleanGetTypeID(),
              remaining.doubleValue.isFinite,
              remaining.doubleValue.rounded() == remaining.doubleValue,
              (0...5).contains(remaining.doubleValue),
              status == .added || destination == nil else {
            throw CloudFunctionsClientError.invalidResponse
        }
        return BrandRequestSubmissionReceipt(
            requestID: try requiredString(dictionary, key: "requestID"),
            groupID: try requiredString(dictionary, key: "groupID"),
            status: status,
            isDuplicate: duplicate.boolValue,
            remainingToday: remaining.intValue,
            resolvedBrandID: destination
        )
    }

    static func nullableBrandID(_ dictionary: [String: Any]) throws -> BrandID? {
        try nullableString(dictionary, key: "resolvedBrandID").map(BrandID.init(value:))
    }

    private static func nullableString(_ dictionary: [String: Any], key: String) throws -> String? {
        guard let value = dictionary[key] else {
            throw CloudFunctionsClientError.missingField(key)
        }
        if value is NSNull { return nil }
        return try requiredString(dictionary, key: key)
    }

    private static func requiredString(_ dictionary: [String: Any], key: String) throws -> String {
        let string = try CloudFunctionResponseDecoder(dictionary: dictionary).string(key)
        guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CloudFunctionsClientError.invalidResponse
        }
        return string
    }

    static func request(_ dictionary: [String: Any]) throws -> BrandRequest {
        let status = try status(dictionary)
        let destination = try nullableBrandID(dictionary)
        let reason = try nullableString(dictionary, key: "rejectionReason")
        let holdReasons = ["공식 룩북 확인 필요", "이용 허락 확인 필요", "브랜드 정보 확인 필요", "기타"]
        guard status == .added || destination == nil,
              status == .rejected ? reason.map(holdReasons.contains) == true : reason == nil else {
            throw CloudFunctionsClientError.invalidResponse
        }
        // 저장된 이름에는 입력 전 정규화의 길이 제한을 다시 적용하지 않는다.
        try validateWebsiteURL(requiredString(dictionary, key: "websiteURL"))
        return BrandRequest(
            id: try requiredString(dictionary, key: "requestID"),
            brandName: try requiredString(dictionary, key: "brandName"),
            normalizedBrandName: "",
            englishBrandName: try nullableString(dictionary, key: "englishBrandName"),
            normalizedEnglishBrandName: nil,
            groupID: try requiredString(dictionary, key: "groupID"),
            dedupeKey: nil, dedupeKeySource: nil,
            status: status, resolvedBrandID: destination, rejectionReason: reason,
            createdAt: try utcDate(dictionary, key: "createdAt"),
            updatedAt: try utcDate(dictionary, key: "updatedAt")
        )
    }

    static func historyPage(_ dictionary: [String: Any], scope: BrandRequestListScope) throws -> BrandRequestPage {
        guard try requiredString(dictionary, key: "scope") == scope.rawValue,
              let rows = dictionary["requests"] as? [[String: Any]], rows.count <= 50,
              let rawCursor = dictionary["nextCursor"] else {
            throw CloudFunctionsClientError.invalidResponse
        }
        let cursor: BrandRequestPage.Cursor?
        if rawCursor is NSNull {
            cursor = nil
        } else {
            guard let raw = rawCursor as? [String: Any] else { throw CloudFunctionsClientError.invalidResponse }
            _ = try utcDate(raw, key: "createdAt")
            cursor = .init(createdAt: try requiredString(raw, key: "createdAt"),
                           requestID: try requiredString(raw, key: "requestID"))
        }
        let requests = try rows.map(request)
        guard requests.allSatisfy({ scope == .active ? [.submitted, .reviewing].contains($0.status)
            : [.added, .rejected].contains($0.status) }) else { throw CloudFunctionsClientError.invalidResponse }
        return BrandRequestPage(requests: requests, nextCursor: cursor, scope: scope)
    }

    private static func utcDate(_ dictionary: [String: Any], key: String) throws -> Date {
        let raw = try requiredString(dictionary, key: key)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard raw.range(of: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$", options: .regularExpression) != nil,
              let date = formatter.date(from: raw), formatter.string(from: date) == raw else {
            throw CloudFunctionsClientError.invalidResponse
        }
        return date
    }

    private static func validateWebsiteURL(_ raw: String) throws {
        guard let parts = URLComponents(string: raw), let url = parts.url,
              ["http", "https"].contains(parts.scheme ?? ""),
              let host = parts.host, !host.isEmpty, host == host.lowercased(),
              parts.user == nil, parts.password == nil, !parts.path.isEmpty,
              !(parts.scheme == "http" && parts.port == 80),
              !(parts.scheme == "https" && parts.port == 443),
              url.standardized.absoluteString == raw else { throw CloudFunctionsClientError.invalidResponse }
    }

    static func failure(_ error: Error) -> BrandRequestFailure? {
        let error = error as NSError
        guard error.domain == FunctionsErrorDomain else { return nil }
        let reason = (error.userInfo[FunctionsErrorDetailsKey] as? [String: Any])?["reason"] as? String
        switch (FunctionsErrorCode(rawValue: error.code), reason) {
        case (.resourceExhausted, "DAILY_LIMIT_REACHED"): return .dailyLimit
        case (.resourceExhausted, "QUERY_BUDGET_EXCEEDED"): return .queryBudget
        case (.permissionDenied, "REQUEST_BLOCKED"): return .requestBlocked
        case (.unauthenticated, _): return .unauthenticated
        case (.permissionDenied, _): return .permissionDenied
        case (.invalidArgument, "INVALID_CURSOR"): return .invalidCursor
        case (.invalidArgument, "INVALID_INPUT"): return .invalidInput
        case (.internal, "DATA_INVALID"): return .invalidStoredData
        case (.unavailable, _): return .unavailable
        default: return nil
        }
    }

}
