//
//  CloudFunctionsSeasonImportRepository.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

/// Cloud Functions를 통해 시즌 URL import job을 생성하는 구현입니다.
struct CloudFunctionsSeasonImportRepository: SeasonImportRequestingRepository {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) {
        self.transport = transport
    }

    func requestSeasonImport(
        brandID: BrandID,
        seasonURL: String,
        sourceCandidateID: String?
    ) async throws -> SeasonImportRequestReceipt {
        var data: [String: Any] = [
            "brandID": brandID.value,
            "seasonURL": seasonURL
        ]
        if let sourceCandidateID { data["sourceCandidateID"] = sourceCandidateID }
        let response = try await transport.call("requestSeasonImport", data: data)
        return try SeasonImportCloudFunctionsMapper.requestReceipt(response)
    }
}
