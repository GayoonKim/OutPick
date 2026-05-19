//
//  SeasonImportJobRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

protocol SeasonImportJobRepositoryProtocol {
    func fetchLatestJobs(
        brandID: BrandID,
        limit: Int
    ) async throws -> [SeasonImportJob]

    func fetchActiveJobs(
        brandID: BrandID
    ) async throws -> [SeasonImportJob]

    func fetchJobs(
        brandID: BrandID,
        sourceCandidateIDs: [String]
    ) async throws -> [SeasonImportJob]
}
