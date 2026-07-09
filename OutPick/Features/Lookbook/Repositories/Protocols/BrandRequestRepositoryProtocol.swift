//
//  BrandRequestRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

protocol BrandRequestRepositoryProtocol {
    func submitBrandRequest(
        brandName: String,
        englishBrandName: String?
    ) async throws -> BrandRequestSubmissionReceipt

    func listMyBrandRequests(
        scope: BrandRequestListScope,
        limit: Int,
        cursor: BrandRequestPage.Cursor?
    ) async throws -> BrandRequestPage

    func listBrandRequestGroups(
        adminStage: BrandRequestAdminStage?,
        processedScope: ProcessedRequestScope?,
        limit: Int,
        cursor: AdminBrandRequestGroupPage.Cursor?
    ) async throws -> AdminBrandRequestGroupPage

    func updateBrandRequestGroupStage(
        groupID: String,
        adminStage: BrandRequestAdminStage,
        rejectionReason: BrandRequestRejectionReason?,
        adminNote: String?
    ) async throws -> AdminBrandRequestGroupStageUpdateReceipt

    func resolveBrandRequestGroup(
        groupID: String,
        resolvedBrandID: BrandID,
        adminNote: String?
    ) async throws -> AdminBrandRequestGroupStageUpdateReceipt

    func markBrandRequestGroupBrandCreated(
        groupID: String,
        createdBrandID: BrandID
    ) async throws -> AdminBrandRequestGroupStageUpdateReceipt
}
