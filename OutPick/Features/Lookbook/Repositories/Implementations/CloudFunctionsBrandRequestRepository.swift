//
//  CloudFunctionsBrandRequestRepository.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

final class CloudFunctionsBrandRequestRepository: BrandRequestRepositoryProtocol {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) {
        self.transport = transport
    }

    func submitBrandRequest(
        brandName: String,
        englishBrandName: String?
    ) async throws -> BrandRequestSubmissionReceipt {
        var data: [String: Any] = ["brandName": brandName]
        if let englishBrandName { data["englishBrandName"] = englishBrandName }
        let response = try await transport.call("submitBrandRequest", data: data)
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        return BrandRequestSubmissionReceipt(
            requestID: try decoder.string("requestID"),
            groupID: decoder.optionalString("groupID"),
            status: BrandRequestStatus(rawValue: try decoder.string("status")) ?? .submitted,
            isDuplicate: decoder.optionalBool("isDuplicate") ?? false,
            remainingToday: decoder.optionalInt("remainingToday") ?? 0
        )
    }

    func listMyBrandRequests(
        scope: BrandRequestListScope,
        limit: Int,
        cursor: BrandRequestPage.Cursor?
    ) async throws -> BrandRequestPage {
        var data: [String: Any] = ["scope": scope.rawValue, "limit": limit]
        if let cursor {
            data["cursorCreatedAt"] = cursor.createdAt
            data["cursorRequestID"] = cursor.requestID
        }
        let response = try await transport.call("listMyBrandRequests", data: data)
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        let nextCursor: BrandRequestPage.Cursor?
        if let raw = response["nextCursor"] as? [String: Any],
           let createdAt = raw["createdAt"] as? String,
           let requestID = raw["requestID"] as? String {
            nextCursor = .init(createdAt: createdAt, requestID: requestID)
        } else {
            nextCursor = nil
        }
        return BrandRequestPage(
            requests: try decoder.dictionaries("requests").map(BrandRequestCloudFunctionsMapper.request),
            nextCursor: nextCursor,
            scope: BrandRequestListScope(
                rawValue: decoder.optionalString("scope") ?? scope.rawValue
            ) ?? scope
        )
    }

    func listBrandRequestGroups(
        adminStage: BrandRequestAdminStage?,
        processedScope: ProcessedRequestScope?,
        limit: Int,
        cursor: AdminBrandRequestGroupPage.Cursor?
    ) async throws -> AdminBrandRequestGroupPage {
        var data: [String: Any] = ["limit": limit]
        if let adminStage { data["adminStage"] = adminStage.rawValue }
        if let processedScope { data["processedScope"] = processedScope.rawValue }
        if let cursor {
            data["cursorUpdatedAt"] = cursor.updatedAt
            data["cursorGroupID"] = cursor.groupID
        }
        let response = try await transport.call("listBrandRequestGroups", data: data)
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        let nextCursor: AdminBrandRequestGroupPage.Cursor?
        if let raw = response["nextCursor"] as? [String: Any],
           let updatedAt = raw["updatedAt"] as? String,
           let groupID = raw["groupID"] as? String {
            nextCursor = .init(updatedAt: updatedAt, groupID: groupID)
        } else {
            nextCursor = nil
        }
        return AdminBrandRequestGroupPage(
            groups: try decoder.dictionaries("groups").map(BrandRequestCloudFunctionsMapper.group),
            nextCursor: nextCursor
        )
    }

    func updateBrandRequestGroupStage(
        groupID: String,
        adminStage: BrandRequestAdminStage,
        rejectionReason: BrandRequestRejectionReason?,
        adminNote: String?
    ) async throws -> AdminBrandRequestGroupStageUpdateReceipt {
        var data: [String: Any] = ["groupID": groupID, "adminStage": adminStage.rawValue]
        if let rejectionReason { data["rejectionReason"] = rejectionReason.rawValue }
        if let adminNote { data["adminNote"] = adminNote }
        let response = try await transport.call("updateBrandRequestGroupStage", data: data)
        return try BrandRequestCloudFunctionsMapper.stageReceipt(
            response,
            fallbackStatus: .submitted,
            fallbackStage: adminStage
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
        if let adminNote { data["adminNote"] = adminNote }
        let response = try await transport.call("resolveBrandRequestGroup", data: data)
        return try BrandRequestCloudFunctionsMapper.stageReceipt(
            response,
            fallbackStatus: .added,
            fallbackStage: .completed
        )
    }

    func markBrandRequestGroupBrandCreated(
        groupID: String,
        createdBrandID: BrandID
    ) async throws -> AdminBrandRequestGroupStageUpdateReceipt {
        let response = try await transport.call(
            "markBrandRequestGroupBrandCreated",
            data: ["groupID": groupID, "createdBrandID": createdBrandID.value]
        )
        return try BrandRequestCloudFunctionsMapper.stageReceipt(
            response,
            fallbackStatus: .reviewing,
            fallbackStage: .processing
        )
    }
}
