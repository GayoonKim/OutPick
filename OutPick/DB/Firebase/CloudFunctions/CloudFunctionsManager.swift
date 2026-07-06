//
//  CloudFunctionsManager.swift
//  OutPick
//
//  Created by 김가윤 on 12/4/25.
//

import Foundation
import FirebaseFunctions

struct KakaoFirebaseAuthBridgeResponse {
    let firebaseCustomToken: String
    let identityKey: String
    let providerUserID: String
    let email: String?
}

struct BrandAdminCapabilitiesResponse {
    let isTotalAdmin: Bool
    let roles: [String]
    let ownedBrandIDs: [String]
    let adminBrandIDs: [String]
}

enum CloudFunctionsManagerError: LocalizedError {
    case invalidResponse
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Cloud Functions 응답 형식이 올바르지 않습니다."
        case .missingField(let field):
            return "Cloud Functions 응답에 \(field) 값이 없습니다."
        }
    }
}

final class CloudFunctionsManager {
    static let shared = CloudFunctionsManager()
    private static let region = "asia-northeast3"

    private lazy var regionalFunctions = Functions.functions(region: Self.region)
    private lazy var defaultFunctions = Functions.functions()

    private init() {}

    func callHelloUser(name: String, completion: @escaping (Result<String, Error>) -> Void) {
        let data: [String: Any] = ["name": name]

        regionalFunctions.httpsCallable("helloUser").call(data) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let dict = result?.data as? [String: Any],
               let text = dict["result"] as? String {
                completion(.success(text))
            } else {
                // 응답 포맷이 예상과 다를 경우
                let parseError = NSError(
                    domain: "CloudFunctions",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "응답 파싱 실패"]
                )
                completion(.failure(parseError))
            }
        }
    }

    func exchangeKakaoToken(accessToken: String) async throws -> KakaoFirebaseAuthBridgeResponse {
        let response = try await callFunction(
            "exchangeKakaoToken",
            data: ["accessToken": accessToken]
        )

        let firebaseCustomToken = try stringValue(response, key: "firebaseCustomToken")
        let identityKey = try stringValue(response, key: "identityKey")
        let providerUserID = try stringValue(response, key: "providerUserID")
        let email = optionalStringValue(response, key: "email")

        return KakaoFirebaseAuthBridgeResponse(
            firebaseCustomToken: firebaseCustomToken,
            identityKey: identityKey,
            providerUserID: providerUserID,
            email: email
        )
    }

    func createBrand(
        name: String,
        englishName: String?,
        isFeatured: Bool,
        websiteURL: String?,
        lookbookArchiveURL: String?
    ) async throws -> String {
        var data: [String: Any] = [
            "name": name,
            "isFeatured": isFeatured
        ]
        if let englishName {
            data["englishName"] = englishName
        }
        if let websiteURL {
            data["websiteURL"] = websiteURL
        }
        if let lookbookArchiveURL {
            data["lookbookArchiveURL"] = lookbookArchiveURL
        }

        let response = try await callFunction("createBrand", data: data)
        return try stringValue(response, key: "brandID")
    }

    func getBrandAdminCapabilities() async throws -> BrandAdminCapabilitiesResponse {
        let response = try await callFunction("getBrandAdminCapabilities", data: [:])

        return BrandAdminCapabilitiesResponse(
            isTotalAdmin: response["isTotalAdmin"] as? Bool ?? false,
            roles: stringArrayValue(response, key: "roles"),
            ownedBrandIDs: stringArrayValue(response, key: "ownedBrandIDs"),
            adminBrandIDs: stringArrayValue(response, key: "adminBrandIDs")
        )
    }

    func updateBrand(
        brandID: String,
        name: String,
        englishName: String?,
        websiteURL: String?,
        lookbookArchiveURL: String?,
        isFeatured: Bool?
    ) async throws -> Brand {
        var data: [String: Any] = [
            "brandID": brandID,
            "name": name,
            "englishName": englishName ?? NSNull(),
            "websiteURL": websiteURL ?? "",
            "lookbookArchiveURL": lookbookArchiveURL ?? ""
        ]
        if let isFeatured {
            data["isFeatured"] = isFeatured
        }

        let response = try await callFunction(
            "updateBrand",
            data: data
        )
        guard let rawBrand = response["brand"] as? [String: Any] else {
            throw CloudFunctionsManagerError.missingField("brand")
        }
        return try brandValue(rawBrand)
    }

    func addBrandManager(
        brandID: String,
        email: String,
        role: BrandManagerRole
    ) async throws -> BrandManagerMutationReceipt {
        let response = try await callFunction(
            "addBrandManager",
            data: [
                "brandID": brandID,
                "email": email,
                "role": role.rawValue
            ]
        )

        return try brandManagerMutationReceipt(response, fallbackRemoved: false)
    }

    func removeBrandManager(
        brandID: String,
        email: String,
        role: BrandManagerRole
    ) async throws -> BrandManagerMutationReceipt {
        let response = try await callFunction(
            "removeBrandManager",
            data: [
                "brandID": brandID,
                "email": email,
                "role": role.rawValue
            ]
        )

        return try brandManagerMutationReceipt(response, fallbackRemoved: true)
    }

    func updateBrandLogoPaths(
        brandID: String,
        logoThumbPath: String? = nil,
        logoDetailPath: String? = nil
    ) async throws -> String {
        var data: [String: Any] = [
            "brandID": brandID
        ]
        if let logoThumbPath {
            data["logoThumbPath"] = logoThumbPath
        }
        if let logoDetailPath {
            data["logoDetailPath"] = logoDetailPath
        }

        let response = try await callFunction(
            "updateBrandLogoPaths",
            data: data
        )
        return try stringValue(response, key: "brandID")
    }

    func setBrandEngagement(
        brandID: String,
        isLiked: Bool
    ) async throws -> BrandEngagementResult {
        let response = try await callFunction(
            "setBrandEngagement",
            data: [
                "brandID": brandID,
                "isLiked": isLiked
            ]
        )

        return BrandEngagementResult(
            brandID: BrandID(value: try stringValue(response, key: "brandID")),
            userID: UserID(value: try stringValue(response, key: "userID")),
            isLiked: try boolValue(response, key: "isLiked"),
            likeCount: try intValue(response, key: "likeCount")
        )
    }

    func setPostEngagement(
        brandID: String,
        seasonID: String,
        postID: String,
        kind: String,
        isEnabled: Bool
    ) async throws -> PostEngagementResult {
        let response = try await callFunction(
            "setPostEngagement",
            data: [
                "brandID": brandID,
                "seasonID": seasonID,
                "postID": postID,
                "kind": kind,
                "isEnabled": isEnabled
            ]
        )

        guard let metricsDictionary = response["metrics"] as? [String: Any] else {
            throw CloudFunctionsManagerError.missingField("metrics")
        }

        return PostEngagementResult(
            brandID: BrandID(value: brandID),
            seasonID: SeasonID(value: seasonID),
            postID: PostID(value: try stringValue(response, key: "postID")),
            userID: UserID(value: try stringValue(response, key: "userID")),
            isLiked: try boolValue(response, key: "isLiked"),
            isSaved: try boolValue(response, key: "isSaved"),
            metrics: try postMetricsValue(metricsDictionary)
        )
    }

    func setSeasonEngagement(
        brandID: String,
        seasonID: String,
        isLiked: Bool
    ) async throws -> SeasonEngagementResult {
        let response = try await callFunction(
            "setSeasonEngagement",
            data: [
                "brandID": brandID,
                "seasonID": seasonID,
                "isLiked": isLiked
            ]
        )

        return SeasonEngagementResult(
            brandID: BrandID(value: try stringValue(response, key: "brandID")),
            seasonID: SeasonID(value: try stringValue(response, key: "seasonID")),
            userID: UserID(value: try stringValue(response, key: "userID")),
            isLiked: try boolValue(response, key: "isLiked"),
            likeCount: try intValue(response, key: "likeCount")
        )
    }

    func setCommentEngagement(
        brandID: String,
        seasonID: String,
        postID: String,
        commentID: String,
        isLiked: Bool
    ) async throws -> CommentEngagementResult {
        let response = try await callFunction(
            "setCommentEngagement",
            data: [
                "brandID": brandID,
                "seasonID": seasonID,
                "postID": postID,
                "commentID": commentID,
                "isLiked": isLiked
            ]
        )

        return CommentEngagementResult(
            brandID: BrandID(value: try stringValue(response, key: "brandID")),
            seasonID: SeasonID(value: try stringValue(response, key: "seasonID")),
            postID: PostID(value: try stringValue(response, key: "postID")),
            commentID: CommentID(value: try stringValue(response, key: "commentID")),
            userID: UserID(value: try stringValue(response, key: "userID")),
            parentCommentID: optionalStringValue(response, key: "parentCommentID")
                .map { CommentID(value: $0) },
            isLiked: try boolValue(response, key: "isLiked"),
            likeCount: try intValue(response, key: "likeCount")
        )
    }

    func createComment(
        brandID: String,
        seasonID: String,
        postID: String,
        message: String
    ) async throws -> CommentMutationResult {
        let response = try await callFunction(
            "createComment",
            data: [
                "brandID": brandID,
                "seasonID": seasonID,
                "postID": postID,
                "message": message
            ]
        )

        return try commentMutationResult(response)
    }

    func createReply(
        brandID: String,
        seasonID: String,
        postID: String,
        parentCommentID: String,
        message: String
    ) async throws -> CommentMutationResult {
        let response = try await callFunction(
            "createReply",
            data: [
                "brandID": brandID,
                "seasonID": seasonID,
                "postID": postID,
                "parentCommentID": parentCommentID,
                "message": message
            ]
        )

        return try commentMutationResult(response)
    }

    func deleteComment(
        brandID: String,
        seasonID: String,
        postID: String,
        commentID: String,
        reason: String?
    ) async throws -> CommentDeletionResult {
        var data: [String: Any] = [
            "brandID": brandID,
            "seasonID": seasonID,
            "postID": postID,
            "commentID": commentID
        ]
        if let reason {
            data["reason"] = reason
        }

        let response = try await callFunction("deleteComment", data: data)
        return try commentDeletionResult(response)
    }

    func reportComment(
        reporterUserID: String,
        target: CommentReportTarget,
        reason: CommentReportReason,
        detail: String?
    ) async throws -> CommentReport {
        var data: [String: Any] = [
            "reporterUserID": reporterUserID,
            "targetType": target.targetType.rawValue,
            "brandID": target.brandID.value,
            "seasonID": target.seasonID.value,
            "postID": target.postID.value,
            "commentID": target.commentID.value,
            "reason": reason.rawValue
        ]
        if let parentCommentID = target.parentCommentID?.value {
            data["parentCommentID"] = parentCommentID
        }
        if let authorNicknameSnapshot = target.authorNicknameSnapshot {
            data["targetAuthorNicknameSnapshot"] = authorNicknameSnapshot
        }
        if let detail {
            data["detail"] = detail
        }

        let response = try await callFunction("reportComment", data: data)
        return try commentReport(response)
    }

    func blockUser(
        blockerUserID: String,
        blockedUserID: String,
        blockedUserNicknameSnapshot: String?,
        source: UserBlockSource
    ) async throws -> UserBlock {
        var data: [String: Any] = [
            "blockerUserID": blockerUserID,
            "blockedUserID": blockedUserID,
            "source": source.rawValue
        ]
        if let blockedUserNicknameSnapshot {
            data["blockedUserNicknameSnapshot"] = blockedUserNicknameSnapshot
        }

        let response = try await callFunction("blockUser", data: data)
        return try userBlock(response)
    }

    func loadHiddenCommentUserIDs(currentUserID: String) async throws -> Set<UserID> {
        let response = try await callFunction(
            "loadHiddenCommentUserIDs",
            data: ["currentUserID": currentUserID]
        )

        return Set(
            stringArrayValue(response, key: "hiddenUserIDs")
                .map { UserID(value: $0) }
        )
    }

    func requestSeasonImport(
        brandID: String,
        seasonURL: String,
        sourceCandidateID: String? = nil
    ) async throws -> SeasonImportRequestReceipt {
        var data: [String: Any] = [
            "brandID": brandID,
            "seasonURL": seasonURL
        ]
        if let sourceCandidateID {
            data["sourceCandidateID"] = sourceCandidateID
        }

        let response = try await callFunction(
            "requestSeasonImport",
            data: data
        )

        return SeasonImportRequestReceipt(
            jobID: try stringValue(response, key: "jobID"),
            status: try stringValue(response, key: "status"),
            normalizedSeasonURL: try stringValue(response, key: "seasonURL"),
            sourceCandidateID: optionalStringValue(response, key: "sourceCandidateID"),
            isDuplicate: optionalBoolValue(response, key: "duplicate") ?? false
        )
    }

    func requestSeasonAssetRetry(
        brandID: String,
        sourceJobID: String
    ) async throws -> SeasonAssetRetryReceipt {
        let response = try await callFunction(
            "requestSeasonAssetRetry",
            data: [
                "brandID": brandID,
                "sourceJobID": sourceJobID
            ]
        )

        return SeasonAssetRetryReceipt(
            sourceImportJobID: try stringValue(
                response,
                key: "sourceImportJobID"
            ),
            seasonID: try stringValue(response, key: "seasonID"),
            status: try stringValue(response, key: "status"),
            isDuplicate: optionalBoolValue(
                response,
                key: "duplicate"
            ) ?? false
        )
    }

    func discoverSeasonCandidates(
        brandID: String
    ) async throws -> SeasonCandidateDiscoveryResult {
        let response = try await callFunction(
            "discoverSeasonCandidates",
            data: [
                "brandID": brandID
            ]
        )

        return SeasonCandidateDiscoveryResult(
            brandID: BrandID(value: try stringValue(response, key: "brandID")),
            sourceURL: try stringValue(response, key: "sourceURL"),
            candidateCount: try intValue(response, key: "candidateCount")
        )
    }

    func requestSeasonCandidateImportJobs(
        brandID: String,
        candidateIDs: [String]
    ) async throws -> SeasonImportBatchRequestResult {
        let response = try await callFunction(
            "requestSeasonCandidateImportJobs",
            data: [
                "brandID": brandID,
                "candidateIDs": candidateIDs
            ]
        )

        return SeasonImportBatchRequestResult(
            brandID: BrandID(value: try stringValue(response, key: "brandID")),
            candidateIDs: stringArrayValue(response, key: "candidateIDs"),
            jobIDs: stringArrayValue(response, key: "jobIDs"),
            requestedJobCount: try intValue(response, key: "requestedJobCount"),
            requestedImportJobCount: optionalIntValue(
                response,
                key: "requestedImportJobCount"
            ) ?? stringArrayValue(response, key: "jobIDs").count,
            createdJobCount: optionalIntValue(response, key: "createdJobCount") ?? 0,
            duplicateJobCount: optionalIntValue(response, key: "duplicateJobCount") ?? 0,
            failedJobCount: try intValue(response, key: "failedJobCount"),
            skippedJobCount: try intValue(response, key: "skippedJobCount"),
            failedCandidates: seasonImportBatchFailures(response)
        )
    }

    func searchBrands(
        query: String,
        limit: Int
    ) async throws -> [Brand] {
        let response = try await callFunction(
            "searchBrands",
            data: [
                "query": query,
                "limit": limit
            ]
        )

        guard let rawBrands = response["brands"] as? [[String: Any]] else {
            throw CloudFunctionsManagerError.missingField("brands")
        }

        return try rawBrands.map { try brandValue($0) }
    }

    func submitBrandRequest(
        brandName: String,
        englishBrandName: String?
    ) async throws -> BrandRequestSubmissionReceipt {
        var data: [String: Any] = ["brandName": brandName]
        if let englishBrandName {
            data["englishBrandName"] = englishBrandName
        }

        let response = try await callFunction(
            "submitBrandRequest",
            data: data
        )

        return BrandRequestSubmissionReceipt(
            requestID: try stringValue(response, key: "requestID"),
            groupID: optionalStringValue(response, key: "groupID"),
            status: BrandRequestStatus(
                rawValue: try stringValue(response, key: "status")
            ) ?? .submitted,
            isDuplicate: optionalBoolValue(response, key: "isDuplicate") ?? false,
            remainingToday: optionalIntValue(response, key: "remainingToday") ?? 0
        )
    }

    func listMyBrandRequests(
        scope: BrandRequestListScope,
        limit: Int,
        cursor: BrandRequestPage.Cursor?
    ) async throws -> BrandRequestPage {
        var data: [String: Any] = [
            "scope": scope.rawValue,
            "limit": limit
        ]
        if let cursor {
            data["cursorCreatedAt"] = cursor.createdAt
            data["cursorRequestID"] = cursor.requestID
        }

        let response = try await callFunction(
            "listMyBrandRequests",
            data: data
        )

        guard let rawRequests = response["requests"] as? [[String: Any]] else {
            throw CloudFunctionsManagerError.missingField("requests")
        }

        let nextCursor: BrandRequestPage.Cursor?
        if let rawCursor = response["nextCursor"] as? [String: Any],
           let createdAt = rawCursor["createdAt"] as? String,
           let requestID = rawCursor["requestID"] as? String {
            nextCursor = BrandRequestPage.Cursor(
                createdAt: createdAt,
                requestID: requestID
            )
        } else {
            nextCursor = nil
        }

        return BrandRequestPage(
            requests: try rawRequests.map { try brandRequestValue($0) },
            nextCursor: nextCursor,
            scope: BrandRequestListScope(
                rawValue: optionalStringValue(response, key: "scope") ?? scope.rawValue
            ) ?? scope
        )
    }

    func listBrandRequestGroups(
        adminStage: BrandRequestAdminStage?,
        limit: Int,
        cursor: AdminBrandRequestGroupPage.Cursor?
    ) async throws -> AdminBrandRequestGroupPage {
        var data: [String: Any] = ["limit": limit]
        if let adminStage {
            data["adminStage"] = adminStage.rawValue
        }
        if let cursor {
            data["cursorUpdatedAt"] = cursor.updatedAt
            data["cursorGroupID"] = cursor.groupID
        }

        let response = try await callFunction(
            "listBrandRequestGroups",
            data: data
        )

        guard let rawGroups = response["groups"] as? [[String: Any]] else {
            throw CloudFunctionsManagerError.missingField("groups")
        }

        let nextCursor: AdminBrandRequestGroupPage.Cursor?
        if let rawCursor = response["nextCursor"] as? [String: Any],
           let updatedAt = rawCursor["updatedAt"] as? String,
           let groupID = rawCursor["groupID"] as? String {
            nextCursor = AdminBrandRequestGroupPage.Cursor(
                updatedAt: updatedAt,
                groupID: groupID
            )
        } else {
            nextCursor = nil
        }

        return AdminBrandRequestGroupPage(
            groups: try rawGroups.map { try brandRequestGroupValue($0) },
            nextCursor: nextCursor
        )
    }

    func updateBrandRequestGroupStage(
        groupID: String,
        adminStage: BrandRequestAdminStage,
        rejectionReason: BrandRequestRejectionReason?,
        adminNote: String?
    ) async throws -> AdminBrandRequestGroupStageUpdateReceipt {
        var data: [String: Any] = [
            "groupID": groupID,
            "adminStage": adminStage.rawValue
        ]
        if let rejectionReason {
            data["rejectionReason"] = rejectionReason.rawValue
        }
        if let adminNote {
            data["adminNote"] = adminNote
        }

        let response = try await callFunction(
            "updateBrandRequestGroupStage",
            data: data
        )

        return AdminBrandRequestGroupStageUpdateReceipt(
            groupID: try stringValue(response, key: "groupID"),
            status: BrandRequestStatus(
                rawValue: try stringValue(response, key: "status")
            ) ?? .submitted,
            adminStage: BrandRequestAdminStage(
                rawValue: try stringValue(response, key: "adminStage")
            ) ?? adminStage,
            updatedRequestCount: optionalIntValue(
                response,
                key: "updatedRequestCount"
            ) ?? 0
        )
    }

    func resolveBrandRequestGroup(
        groupID: String,
        resolvedBrandID: BrandID,
        adminNote: String?
    ) async throws -> AdminBrandRequestGroupStageUpdateReceipt {
        var data: [String: Any] = [
            "groupID": groupID,
            "resolvedBrandID": resolvedBrandID.value
        ]
        if let adminNote {
            data["adminNote"] = adminNote
        }

        let response = try await callFunction(
            "resolveBrandRequestGroup",
            data: data
        )

        return AdminBrandRequestGroupStageUpdateReceipt(
            groupID: try stringValue(response, key: "groupID"),
            status: BrandRequestStatus(
                rawValue: try stringValue(response, key: "status")
            ) ?? .added,
            adminStage: BrandRequestAdminStage(
                rawValue: try stringValue(response, key: "adminStage")
            ) ?? .completed,
            updatedRequestCount: optionalIntValue(
                response,
                key: "updatedRequestCount"
            ) ?? 0
        )
    }

    func markBrandRequestGroupBrandCreated(
        groupID: String,
        createdBrandID: BrandID
    ) async throws -> AdminBrandRequestGroupStageUpdateReceipt {
        let response = try await callFunction(
            "markBrandRequestGroupBrandCreated",
            data: [
                "groupID": groupID,
                "createdBrandID": createdBrandID.value
            ]
        )

        return AdminBrandRequestGroupStageUpdateReceipt(
            groupID: try stringValue(response, key: "groupID"),
            status: BrandRequestStatus(
                rawValue: try stringValue(response, key: "status")
            ) ?? .reviewing,
            adminStage: BrandRequestAdminStage(
                rawValue: try stringValue(response, key: "adminStage")
            ) ?? .processing,
            updatedRequestCount: optionalIntValue(
                response,
                key: "updatedRequestCount"
            ) ?? 0
        )
    }

    private func callFunction(
        _ name: String,
        data: [String: Any],
        functions: Functions? = nil
    ) async throws -> [String: Any] {
        let functionsClient = functions ?? regionalFunctions

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
            functionsClient.httpsCallable(name).call(data) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let dictionary = result?.data as? [String: Any] else {
                    continuation.resume(throwing: CloudFunctionsManagerError.invalidResponse)
                    return
                }

                continuation.resume(returning: dictionary)
            }
        }
    }

    private func stringValue(_ dictionary: [String: Any], key: String) throws -> String {
        guard let value = dictionary[key] as? String, !value.isEmpty else {
            throw CloudFunctionsManagerError.missingField(key)
        }
        return value
    }

    private func boolValue(_ dictionary: [String: Any], key: String) throws -> Bool {
        if let value = dictionary[key] as? Bool {
            return value
        }
        if let value = dictionary[key] as? NSNumber {
            return value.boolValue
        }
        throw CloudFunctionsManagerError.missingField(key)
    }

    private func intValue(_ dictionary: [String: Any], key: String) throws -> Int {
        if let value = dictionary[key] as? Int {
            return value
        }
        if let value = dictionary[key] as? NSNumber {
            return value.intValue
        }
        throw CloudFunctionsManagerError.missingField(key)
    }

    private func optionalStringValue(_ dictionary: [String: Any], key: String) -> String? {
        guard let value = dictionary[key], !(value is NSNull) else {
            return nil
        }
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func optionalIntValue(_ dictionary: [String: Any], key: String) -> Int? {
        guard let value = dictionary[key], !(value is NSNull) else {
            return nil
        }
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private func optionalBoolValue(_ dictionary: [String: Any], key: String) -> Bool? {
        guard let value = dictionary[key], !(value is NSNull) else {
            return nil
        }
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    private func dateValue(_ dictionary: [String: Any], key: String) throws -> Date {
        if let value = dictionary[key] as? TimeInterval {
            return Date(timeIntervalSince1970: value / 1000)
        }
        if let value = dictionary[key] as? NSNumber {
            return Date(timeIntervalSince1970: value.doubleValue / 1000)
        }
        throw CloudFunctionsManagerError.missingField(key)
    }

    private func optionalDateValue(_ dictionary: [String: Any], key: String) -> Date? {
        guard let value = dictionary[key], !(value is NSNull) else {
            return nil
        }
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue / 1000)
        }
        if let string = value as? String {
            return ISO8601DateFormatter().date(from: string)
        }
        return nil
    }

    private func brandValue(_ dictionary: [String: Any]) throws -> Brand {
        let metricsDictionary = dictionary["metrics"] as? [String: Any] ?? [:]

        return Brand(
            id: BrandID(value: try stringValue(dictionary, key: "brandID")),
            name: try stringValue(dictionary, key: "name"),
            englishName: optionalStringValue(dictionary, key: "englishName"),
            websiteURL: optionalStringValue(dictionary, key: "websiteURL"),
            lookbookArchiveURL: optionalStringValue(dictionary, key: "lookbookArchiveURL"),
            logoThumbPath: optionalStringValue(dictionary, key: "logoThumbPath"),
            logoDetailPath: optionalStringValue(dictionary, key: "logoDetailPath"),
            logoOriginalPath: optionalStringValue(dictionary, key: "logoOriginalPath"),
            isFeatured: optionalBoolValue(dictionary, key: "isFeatured") ?? false,
            discoveryStatus: BrandDiscoveryStatus(
                rawValue: optionalStringValue(dictionary, key: "discoveryStatus") ?? ""
            ) ?? .idle,
            lastDiscoveryErrorMessage: optionalStringValue(dictionary, key: "lastDiscoveryErrorMessage"),
            lastDiscoveryRequestedAt: optionalDateValue(dictionary, key: "lastDiscoveryRequestedAt"),
            lastDiscoveryCompletedAt: optionalDateValue(dictionary, key: "lastDiscoveryCompletedAt"),
            metrics: BrandMetrics(
                likeCount: optionalIntValue(metricsDictionary, key: "likeCount") ?? 0,
                viewCount: optionalIntValue(metricsDictionary, key: "viewCount") ?? 0,
                popularScore: optionalDoubleValue(metricsDictionary, key: "popularScore") ?? 0
            ),
            updatedAt: optionalDateValue(dictionary, key: "updatedAt") ?? Date(timeIntervalSince1970: 0)
        )
    }

    private func brandRequestValue(_ dictionary: [String: Any]) throws -> BrandRequest {
        BrandRequest(
            id: try stringValue(dictionary, key: "requestID"),
            brandName: try stringValue(dictionary, key: "brandName"),
            normalizedBrandName: optionalStringValue(dictionary, key: "normalizedBrandName") ?? "",
            englishBrandName: optionalStringValue(dictionary, key: "englishBrandName"),
            normalizedEnglishBrandName: optionalStringValue(dictionary, key: "normalizedEnglishBrandName"),
            groupID: optionalStringValue(dictionary, key: "groupID"),
            dedupeKey: optionalStringValue(dictionary, key: "dedupeKey"),
            dedupeKeySource: optionalStringValue(dictionary, key: "dedupeKeySource"),
            status: BrandRequestStatus(
                rawValue: try stringValue(dictionary, key: "status")
            ) ?? .submitted,
            resolvedBrandID: optionalStringValue(dictionary, key: "resolvedBrandID")
                .map { BrandID(value: $0) },
            rejectionReason: optionalStringValue(dictionary, key: "rejectionReason"),
            createdAt: optionalDateValue(dictionary, key: "createdAt"),
            updatedAt: optionalDateValue(dictionary, key: "updatedAt")
        )
    }

    private func brandRequestGroupValue(
        _ dictionary: [String: Any]
    ) throws -> AdminBrandRequestGroup {
        AdminBrandRequestGroup(
            id: try stringValue(dictionary, key: "groupID"),
            dedupeKey: optionalStringValue(dictionary, key: "dedupeKey") ?? "",
            dedupeKeySource: optionalStringValue(dictionary, key: "dedupeKeySource") ?? "",
            displayNameSnapshot: try stringValue(dictionary, key: "displayNameSnapshot"),
            normalizedBrandName: optionalStringValue(
                dictionary,
                key: "normalizedBrandName"
            ) ?? "",
            englishBrandName: optionalStringValue(dictionary, key: "englishBrandName"),
            normalizedEnglishBrandName: optionalStringValue(
                dictionary,
                key: "normalizedEnglishBrandName"
            ),
            requestCount: optionalIntValue(dictionary, key: "requestCount") ?? 0,
            adminStage: BrandRequestAdminStage(
                rawValue: try stringValue(dictionary, key: "adminStage")
            ) ?? .requested,
            status: BrandRequestStatus(
                rawValue: try stringValue(dictionary, key: "status")
            ) ?? .submitted,
            rejectionReason: optionalStringValue(dictionary, key: "rejectionReason")
                .flatMap { BrandRequestRejectionReason(rawValue: $0) },
            resolvedBrandID: optionalStringValue(dictionary, key: "resolvedBrandID")
                .map { BrandID(value: $0) },
            createdBrandID: optionalStringValue(dictionary, key: "createdBrandID")
                .map { BrandID(value: $0) },
            brandCreatedAt: optionalDateValue(dictionary, key: "brandCreatedAt"),
            brandCreatedBy: optionalStringValue(dictionary, key: "brandCreatedBy"),
            adminNote: optionalStringValue(dictionary, key: "adminNote"),
            lastRequestID: optionalStringValue(dictionary, key: "lastRequestID"),
            lastRequestedAt: optionalDateValue(dictionary, key: "lastRequestedAt"),
            createdAt: optionalDateValue(dictionary, key: "createdAt"),
            updatedAt: optionalDateValue(dictionary, key: "updatedAt"),
            reviewedAt: optionalDateValue(dictionary, key: "reviewedAt"),
            resolvedAt: optionalDateValue(dictionary, key: "resolvedAt"),
            rejectedAt: optionalDateValue(dictionary, key: "rejectedAt")
        )
    }

    private func brandManagerMutationReceipt(
        _ dictionary: [String: Any],
        fallbackRemoved: Bool
    ) throws -> BrandManagerMutationReceipt {
        BrandManagerMutationReceipt(
            brandID: BrandID(value: try stringValue(dictionary, key: "brandID")),
            userID: UserID(value: try stringValue(dictionary, key: "uid")),
            email: try stringValue(dictionary, key: "email"),
            role: BrandManagerRole(
                rawValue: try stringValue(dictionary, key: "role")
            ) ?? .admin,
            duplicate: optionalBoolValue(dictionary, key: "duplicate") ?? false,
            removed: optionalBoolValue(dictionary, key: "removed") ?? fallbackRemoved
        )
    }

    private func optionalDoubleValue(_ dictionary: [String: Any], key: String) -> Double? {
        guard let value = dictionary[key], !(value is NSNull) else {
            return nil
        }
        if let double = value as? Double {
            return double
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return nil
    }

    private func postMetricsValue(_ dictionary: [String: Any]) throws -> PostMetrics {
        PostMetrics(
            likeCount: try intValue(dictionary, key: "likeCount"),
            commentCount: try intValue(dictionary, key: "commentCount"),
            replacementCount: try intValue(dictionary, key: "replacementCount"),
            saveCount: try intValue(dictionary, key: "saveCount"),
            viewCount: optionalIntValue(dictionary, key: "viewCount")
        )
    }

    private func seasonImportBatchFailures(
        _ dictionary: [String: Any]
    ) -> [SeasonImportBatchFailure] {
        guard let rawItems = dictionary["failedCandidates"] as? [[String: Any]] else {
            return []
        }

        return rawItems.compactMap { item in
            guard let candidateID = item["candidateID"] as? String,
                  !candidateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }

            return SeasonImportBatchFailure(
                candidateID: candidateID,
                title: optionalStringValue(item, key: "title"),
                errorMessage: optionalStringValue(item, key: "errorMessage")
                    ?? "시즌 가져오기 작업을 준비하지 못했습니다."
            )
        }
    }

    private func commentMutationResult(
        _ dictionary: [String: Any]
    ) throws -> CommentMutationResult {
        CommentMutationResult(
            brandID: BrandID(value: try stringValue(dictionary, key: "brandID")),
            seasonID: SeasonID(value: try stringValue(dictionary, key: "seasonID")),
            postID: PostID(value: try stringValue(dictionary, key: "postID")),
            commentID: CommentID(value: try stringValue(dictionary, key: "commentID")),
            userID: UserID(value: try stringValue(dictionary, key: "userID")),
            parentCommentID: optionalStringValue(dictionary, key: "parentCommentID")
                .map { CommentID(value: $0) },
            commentCount: try intValue(dictionary, key: "commentCount"),
            replyCount: try intValue(dictionary, key: "replyCount")
        )
    }

    private func commentDeletionResult(
        _ dictionary: [String: Any]
    ) throws -> CommentDeletionResult {
        CommentDeletionResult(
            brandID: BrandID(value: try stringValue(dictionary, key: "brandID")),
            seasonID: SeasonID(value: try stringValue(dictionary, key: "seasonID")),
            postID: PostID(value: try stringValue(dictionary, key: "postID")),
            commentID: CommentID(value: try stringValue(dictionary, key: "commentID")),
            userID: UserID(value: try stringValue(dictionary, key: "userID")),
            parentCommentID: optionalStringValue(dictionary, key: "parentCommentID")
                .map { CommentID(value: $0) },
            targetType: CommentSafetyTargetType(
                rawValue: try stringValue(dictionary, key: "targetType")
            ) ?? .comment,
            deletedReplyCount: try intValue(dictionary, key: "deletedReplyCount"),
            deletedCommentCount: try intValue(dictionary, key: "deletedCommentCount"),
            commentCount: try intValue(dictionary, key: "commentCount"),
            replyCount: try intValue(dictionary, key: "replyCount")
        )
    }

    private func commentReport(
        _ dictionary: [String: Any]
    ) throws -> CommentReport {
        let target = CommentReportTarget(
            targetType: CommentSafetyTargetType(
                rawValue: try stringValue(dictionary, key: "targetType")
            ) ?? .comment,
            brandID: BrandID(value: try stringValue(dictionary, key: "brandID")),
            seasonID: SeasonID(value: try stringValue(dictionary, key: "seasonID")),
            postID: PostID(value: try stringValue(dictionary, key: "postID")),
            commentID: CommentID(value: try stringValue(dictionary, key: "targetCommentID")),
            parentCommentID: optionalStringValue(dictionary, key: "parentCommentID")
                .map { CommentID(value: $0) },
            authorID: UserID(value: try stringValue(dictionary, key: "targetAuthorID")),
            contentSnapshot: try stringValue(dictionary, key: "targetContentSnapshot"),
            authorNicknameSnapshot: optionalStringValue(dictionary, key: "targetAuthorNicknameSnapshot")
        )

        return CommentReport(
            id: CommentReportID(value: try stringValue(dictionary, key: "reportID")),
            reporterUserID: UserID(value: try stringValue(dictionary, key: "reporterUserID")),
            target: target,
            reason: CommentReportReason(rawValue: try stringValue(dictionary, key: "reason")) ?? .other,
            detail: optionalStringValue(dictionary, key: "detail"),
            status: CommentReportStatus(rawValue: try stringValue(dictionary, key: "status")) ?? .pending,
            createdAt: try dateValue(dictionary, key: "createdAtMillis")
        )
    }

    private func userBlock(
        _ dictionary: [String: Any]
    ) throws -> UserBlock {
        UserBlock(
            blockerUserID: UserID(value: try stringValue(dictionary, key: "blockerUserID")),
            blockedUserID: UserID(value: try stringValue(dictionary, key: "blockedUserID")),
            blockedUserNicknameSnapshot: optionalStringValue(
                dictionary,
                key: "blockedUserNicknameSnapshot"
            ),
            source: UserBlockSource(rawValue: try stringValue(dictionary, key: "source")) ?? .profile,
            createdAt: try dateValue(dictionary, key: "createdAtMillis")
        )
    }

    private func stringArrayValue(_ dictionary: [String: Any], key: String) -> [String] {
        guard let values = dictionary[key] as? [String] else {
            return []
        }
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
