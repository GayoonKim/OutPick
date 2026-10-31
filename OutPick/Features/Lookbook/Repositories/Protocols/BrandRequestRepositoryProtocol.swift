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
        websiteURL: String,
        englishBrandName: String?
    ) async throws -> BrandRequestSubmissionReceipt

    func listMyBrandRequests(
        scope: BrandRequestListScope,
        limit: Int,
        cursor: BrandRequestPage.Cursor?
    ) async throws -> BrandRequestPage
}
