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
}
