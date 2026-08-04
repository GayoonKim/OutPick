//
//  SeasonCandidateDiscoveryResult.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

enum SeasonDiscoveryJobStatus: String, Equatable {
    case queued
    case dispatching
    case running
    case succeeded
    case awaitingReview
    case correctionRequired
    case failed
    case cancelled
    case superseded
    case unknown

    var isActive: Bool {
        self == .queued || self == .dispatching || self == .running
    }
}

struct SeasonCandidateDiscoveryResult: Equatable {
    enum ImprovementState: Equatable {
        case unavailable
        case requestable
        case requested
        case ready
    }

    let brandID: BrandID
    let jobID: String
    let generation: Int
    let status: SeasonDiscoveryJobStatus
    let sourceURL: String
    let candidateCount: Int
    let candidateSnapshotHash: String?
    let newSeasonCandidateCount: Int
    let reviewCandidateCount: Int
    let matchedCandidateCount: Int
    let phase: String?
    let errorMessage: String?
    let retryable: Bool
    let recommendedAction: String
    let improvementRequested: Bool
    let blockedByExtractionContractRevision: Int?
    let availableExtractionContractRevision: Int?
    let requestedAt: Date?
    let completedAt: Date?

    init(
        brandID: BrandID,
        jobID: String,
        generation: Int,
        status: SeasonDiscoveryJobStatus,
        sourceURL: String,
        candidateCount: Int,
        candidateSnapshotHash: String?,
        newSeasonCandidateCount: Int = 0,
        reviewCandidateCount: Int = 0,
        matchedCandidateCount: Int = 0,
        phase: String? = nil,
        errorMessage: String? = nil,
        retryable: Bool = false,
        recommendedAction: String = "none",
        improvementRequested: Bool = false,
        blockedByExtractionContractRevision: Int? = nil,
        availableExtractionContractRevision: Int? = nil,
        requestedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.brandID = brandID
        self.jobID = jobID
        self.generation = generation
        self.status = status
        self.sourceURL = sourceURL
        self.candidateCount = candidateCount
        self.candidateSnapshotHash = candidateSnapshotHash
        self.newSeasonCandidateCount = newSeasonCandidateCount
        self.reviewCandidateCount = reviewCandidateCount
        self.matchedCandidateCount = matchedCandidateCount
        self.phase = phase
        self.errorMessage = errorMessage
        self.retryable = retryable
        self.recommendedAction = recommendedAction
        self.improvementRequested = improvementRequested
        self.blockedByExtractionContractRevision = blockedByExtractionContractRevision
        self.availableExtractionContractRevision = availableExtractionContractRevision
        self.requestedAt = requestedAt
        self.completedAt = completedAt
    }

    var improvementState: ImprovementState {
        guard status == .correctionRequired else { return .unavailable }
        if recommendedAction == "reanalyzeWithNewVersion",
           let availableExtractionContractRevision,
           availableExtractionContractRevision > (blockedByExtractionContractRevision ?? 0) {
            return .ready
        }
        return improvementRequested ? .requested : .requestable
    }

    func markingImprovementRequested() -> Self {
        Self(
            brandID: brandID,
            jobID: jobID,
            generation: generation,
            status: status,
            sourceURL: sourceURL,
            candidateCount: candidateCount,
            candidateSnapshotHash: candidateSnapshotHash,
            newSeasonCandidateCount: newSeasonCandidateCount,
            reviewCandidateCount: reviewCandidateCount,
            matchedCandidateCount: matchedCandidateCount,
            phase: phase,
            errorMessage: errorMessage,
            retryable: retryable,
            recommendedAction: "waitForExtractorFix",
            improvementRequested: true,
            blockedByExtractionContractRevision: blockedByExtractionContractRevision,
            availableExtractionContractRevision: availableExtractionContractRevision,
            requestedAt: requestedAt,
            completedAt: completedAt
        )
    }
}

struct SeasonDiscoveryReviewCandidate: Equatable, Identifiable {
    let id: String
    let title: String
    let seasonURL: String
    let coverImageURL: String?
    let resolution: String
    let matchedSeasonID: SeasonID?
}
