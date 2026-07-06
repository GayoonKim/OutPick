//
//  CloudFunctionsBrandRequestRepository.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

final class CloudFunctionsBrandRequestRepository: BrandRequestRepositoryProtocol {
    private let cloudFunctionsManager: CloudFunctionsManager

    init(cloudFunctionsManager: CloudFunctionsManager = .shared) {
        self.cloudFunctionsManager = cloudFunctionsManager
    }

    func submitBrandRequest(
        brandName: String,
        englishBrandName: String?
    ) async throws -> BrandRequestSubmissionReceipt {
        try await cloudFunctionsManager.submitBrandRequest(
            brandName: brandName,
            englishBrandName: englishBrandName
        )
    }

    func listMyBrandRequests(
        scope: BrandRequestListScope,
        limit: Int,
        cursor: BrandRequestPage.Cursor?
    ) async throws -> BrandRequestPage {
        try await cloudFunctionsManager.listMyBrandRequests(
            scope: scope,
            limit: limit,
            cursor: cursor
        )
    }

    func listBrandRequestGroups(
        adminStage: BrandRequestAdminStage?,
        limit: Int,
        cursor: AdminBrandRequestGroupPage.Cursor?
    ) async throws -> AdminBrandRequestGroupPage {
        try await cloudFunctionsManager.listBrandRequestGroups(
            adminStage: adminStage,
            limit: limit,
            cursor: cursor
        )
    }

    func updateBrandRequestGroupStage(
        groupID: String,
        adminStage: BrandRequestAdminStage,
        rejectionReason: BrandRequestRejectionReason?,
        adminNote: String?
    ) async throws -> AdminBrandRequestGroupStageUpdateReceipt {
        try await cloudFunctionsManager.updateBrandRequestGroupStage(
            groupID: groupID,
            adminStage: adminStage,
            rejectionReason: rejectionReason,
            adminNote: adminNote
        )
    }

    func resolveBrandRequestGroup(
        groupID: String,
        resolvedBrandID: BrandID,
        adminNote: String?
    ) async throws -> AdminBrandRequestGroupStageUpdateReceipt {
        try await cloudFunctionsManager.resolveBrandRequestGroup(
            groupID: groupID,
            resolvedBrandID: resolvedBrandID,
            adminNote: adminNote
        )
    }

    func markBrandRequestGroupBrandCreated(
        groupID: String,
        createdBrandID: BrandID
    ) async throws -> AdminBrandRequestGroupStageUpdateReceipt {
        try await cloudFunctionsManager.markBrandRequestGroupBrandCreated(
            groupID: groupID,
            createdBrandID: createdBrandID
        )
    }
}
