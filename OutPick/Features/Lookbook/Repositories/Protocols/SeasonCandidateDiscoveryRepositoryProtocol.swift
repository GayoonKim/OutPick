//
//  SeasonCandidateDiscoveryRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

protocol SeasonCandidateDiscoveryRepositoryProtocol {
    func requestSeasonDiscovery(
        brandID: BrandID
    ) async throws -> SeasonCandidateDiscoveryResult

    func discoverSeasonCandidates(
        brandID: BrandID
    ) async throws -> SeasonCandidateDiscoveryResult

    func observeSeasonDiscovery(
        brandID: BrandID,
        jobID: String
    ) async throws -> SeasonCandidateDiscoveryResult

    func observeLatestSeasonDiscovery(
        brandID: BrandID
    ) -> AsyncThrowingStream<SeasonCandidateDiscoveryResult?, Error>

    func retrySeasonDiscovery(brandID: BrandID, jobID: String) async throws
    func cancelSeasonDiscovery(brandID: BrandID, jobID: String) async throws
    func requestSeasonDiscoveryImprovement(
        brandID: BrandID,
        job: SeasonCandidateDiscoveryResult
    ) async throws
    func reanalyzeSeasonDiscoveryWithLatestExtractor(
        brandID: BrandID,
        job: SeasonCandidateDiscoveryResult
    ) async throws -> SeasonCandidateDiscoveryResult

    func fetchReviewCandidates(
        brandID: BrandID,
        jobID: String
    ) async throws -> [SeasonDiscoveryReviewCandidate]

    func resolveReviewCandidate(
        brandID: BrandID,
        job: SeasonCandidateDiscoveryResult,
        candidateID: String,
        decision: String,
        targetSeasonID: SeasonID?
    ) async throws
}
