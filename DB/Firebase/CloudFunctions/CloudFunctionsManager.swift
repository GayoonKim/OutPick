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
    let canCreateBrands: Bool
    let roles: [String]
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
        isFeatured: Bool,
        websiteURL: String?,
        lookbookArchiveURL: String?
    ) async throws -> String {
        var data: [String: Any] = [
            "name": name,
            "isFeatured": isFeatured
        ]
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
        let response: [String: Any]
        do {
            response = try await callFunction("getBrandAdminCapabilities", data: [:])
        } catch {
            let nsError = error as NSError
            print(
                """
                [CloudFunctionsManager] getBrandAdminCapabilities failed \
                region=\(Self.region) domain=\(nsError.domain) code=\(nsError.code) \
                description=\(nsError.localizedDescription). Retrying default region.
                """
            )
            response = try await callFunction(
                "getBrandAdminCapabilities",
                data: [:],
                functions: defaultFunctions
            )
        }

        return BrandAdminCapabilitiesResponse(
            canCreateBrands: response["canCreateBrands"] as? Bool ?? false,
            roles: stringArrayValue(response, key: "roles")
        )
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
            postID: PostID(value: try stringValue(response, key: "postID")),
            userID: UserID(value: try stringValue(response, key: "userID")),
            isLiked: try boolValue(response, key: "isLiked"),
            isSaved: try boolValue(response, key: "isSaved"),
            metrics: try postMetricsValue(metricsDictionary)
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

    func processNextSeasonImportJob(
        brandID: String
    ) async throws -> SeasonImportProcessResult {
        let response = try await callFunction(
            "processNextSeasonImportJob",
            data: [
                "brandID": brandID
            ]
        )

        return SeasonImportProcessResult(
            processed: try boolValue(response, key: "processed"),
            reason: optionalStringValue(response, key: "reason"),
            brandID: optionalStringValue(response, key: "brandID")
                .map { BrandID(value: $0) },
            jobID: optionalStringValue(response, key: "jobID"),
            sourceURL: optionalStringValue(response, key: "sourceURL"),
            imageCandidateCount: optionalIntValue(
                response,
                key: "imageCandidateCount"
            )
        )
    }

    func processSeasonImportJobs(
        brandID: String,
        jobIDs: [String]
    ) async throws -> SeasonImportBatchProcessResult {
        let response = try await callFunction(
            "processSeasonImportJobs",
            data: [
                "brandID": brandID,
                "jobIDs": jobIDs
            ]
        )

        return SeasonImportBatchProcessResult(
            brandID: BrandID(value: try stringValue(response, key: "brandID")),
            candidateIDs: stringArrayValue(response, key: "candidateIDs"),
            jobIDs: stringArrayValue(response, key: "jobIDs"),
            requestedJobCount: try intValue(response, key: "requestedJobCount"),
            duplicateJobCount: optionalIntValue(response, key: "duplicateJobCount") ?? 0,
            processedJobCount: try intValue(response, key: "processedJobCount"),
            failedJobCount: try intValue(response, key: "failedJobCount"),
            skippedJobCount: try intValue(response, key: "skippedJobCount")
        )
    }

    func requestSeasonCandidateImportsAndProcess(
        brandID: String,
        candidateIDs: [String]
    ) async throws -> SeasonImportBatchProcessResult {
        let response = try await callFunction(
            "requestSeasonCandidateImportsAndProcess",
            data: [
                "brandID": brandID,
                "candidateIDs": candidateIDs
            ]
        )

        return SeasonImportBatchProcessResult(
            brandID: BrandID(value: try stringValue(response, key: "brandID")),
            candidateIDs: stringArrayValue(response, key: "candidateIDs"),
            jobIDs: stringArrayValue(response, key: "jobIDs"),
            requestedJobCount: try intValue(response, key: "requestedJobCount"),
            duplicateJobCount: optionalIntValue(response, key: "duplicateJobCount") ?? 0,
            processedJobCount: try intValue(response, key: "processedJobCount"),
            failedJobCount: try intValue(response, key: "failedJobCount"),
            skippedJobCount: try intValue(response, key: "skippedJobCount")
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

    private func postMetricsValue(_ dictionary: [String: Any]) throws -> PostMetrics {
        PostMetrics(
            likeCount: try intValue(dictionary, key: "likeCount"),
            commentCount: try intValue(dictionary, key: "commentCount"),
            replacementCount: try intValue(dictionary, key: "replacementCount"),
            saveCount: try intValue(dictionary, key: "saveCount"),
            viewCount: optionalIntValue(dictionary, key: "viewCount")
        )
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
