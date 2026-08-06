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
    let extractionIssueStatus: ExtractionIssueStatus?
    let retryAvailableRuntimeVersion: String?
    let extractionIssueWontFixReason: String?
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
        extractionIssueStatus: ExtractionIssueStatus? = nil,
        retryAvailableRuntimeVersion: String? = nil,
        extractionIssueWontFixReason: String? = nil,
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
        self.extractionIssueStatus = extractionIssueStatus
        self.retryAvailableRuntimeVersion = retryAvailableRuntimeVersion
        self.extractionIssueWontFixReason = extractionIssueWontFixReason
        self.requestedAt = requestedAt
        self.completedAt = completedAt
    }

    var extractionIssueUserState: ExtractionIssueUserState {
        guard status == .correctionRequired else { return .unavailable }
        return extractionIssueStatus?.userState ?? .unavailable
    }

    var canRetryExtractionAfterFix: Bool {
        extractionIssueUserState == .retryReady &&
            retryAvailableRuntimeVersion?.isEmpty == false
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
