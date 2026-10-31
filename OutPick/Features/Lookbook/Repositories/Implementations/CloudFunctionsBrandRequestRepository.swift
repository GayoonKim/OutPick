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





}
