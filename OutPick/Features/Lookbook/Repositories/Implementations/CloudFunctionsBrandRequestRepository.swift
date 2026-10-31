//
//  CloudFunctionsBrandRequestRepository.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

final class CloudFunctionsBrandRequestRepository: BrandRequestRepositoryProtocol {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport(
        preservingErrorDetailsForCalls: ["submitBrandRequest", "listMyBrandRequests"])) {
        self.transport = transport
    }

    func submitBrandRequest(
        brandName: String,
        websiteURL: String,
        englishBrandName: String?
    ) async throws -> BrandRequestSubmissionReceipt {
        var data: [String: Any] = ["brandName": brandName, "websiteURL": websiteURL]
        if let englishBrandName { data["englishBrandName"] = englishBrandName }
        let response = try await publicCall("submitBrandRequest", data: data)
        return try BrandRequestCloudFunctionsMapper.submissionReceipt(response)
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
        let response = try await publicCall("listMyBrandRequests", data: data)
        return try BrandRequestCloudFunctionsMapper.historyPage(response, scope: scope)
    }

    private func publicCall(_ name: String, data: [String: Any]) async throws -> [String: Any] {
        do { return try await transport.call(name, data: data) }
        catch {
            if let failure = BrandRequestCloudFunctionsMapper.failure(error) { throw failure }
            throw error
        }
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
