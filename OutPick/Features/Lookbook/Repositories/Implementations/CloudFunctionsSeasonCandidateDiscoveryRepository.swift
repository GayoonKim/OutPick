//
//  CloudFunctionsSeasonCandidateDiscoveryRepository.swift
//  OutPick
//

import Foundation
import FirebaseFirestore

enum SeasonCandidateDiscoveryError: LocalizedError {
    case failed(message: String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}

struct CloudFunctionsSeasonCandidateDiscoveryRepository: SeasonCandidateDiscoveryRepositoryProtocol {
    typealias JobObserver = (BrandID, String) -> AsyncThrowingStream<[String: Any], Error>

    private let transport: any CloudFunctionsTransporting
    private let db: Firestore
    private let observeJob: JobObserver

    init(
        transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport(),
        db: Firestore = .firestore(),
        observeJob: JobObserver? = nil
    ) {
        self.transport = transport
        self.db = db
        self.observeJob = observeJob ?? { brandID, jobID in
            Self.jobStream(db: db, brandID: brandID, jobID: jobID)
        }
    }

    func discoverSeasonCandidates(
        brandID: BrandID
    ) async throws -> SeasonCandidateDiscoveryResult {
        let receipt = try await requestSeasonDiscovery(brandID: brandID)
        return try await observeSeasonDiscovery(
            brandID: brandID,
            jobID: receipt.jobID
        )
    }

    func requestSeasonDiscovery(
        brandID: BrandID
    ) async throws -> SeasonCandidateDiscoveryResult {
        let response = try await transport.call(
            "requestSeasonDiscovery",
            data: [
                "brandID": brandID.value,
                "requestReason": "manualRefresh"
            ]
        )
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        let jobID = try decoder.string("jobID")
        let generation = try decoder.int("generation")
        let sourceURL = try decoder.string("sourceArchiveURL")

        return SeasonCandidateDiscoveryResult(
            brandID: brandID,
            jobID: jobID,
            generation: generation,
            status: .queued,
            sourceURL: sourceURL,
            candidateCount: 0,
            candidateSnapshotHash: nil,
            requestedAt: Date()
        )
    }

    func observeSeasonDiscovery(
        brandID: BrandID,
        jobID: String
    ) async throws -> SeasonCandidateDiscoveryResult {
        try await observeJobResult(
            brandID: brandID,
            jobID: jobID,
            generation: nil,
            sourceURL: nil
        )
    }

    private func observeJobResult(
        brandID: BrandID,
        jobID: String,
        generation: Int?,
        sourceURL: String?
    ) async throws -> SeasonCandidateDiscoveryResult {
        for try await data in observeJob(brandID, jobID) {
            guard let status = data["status"] as? String else { continue }
            if ["queued", "dispatching", "running"].contains(status) { continue }
            if status == "failed" || status == "cancelled" || status == "superseded" {
                let message = data["errorMessage"] as? String
                    ?? "시즌 탐색을 완료하지 못했습니다."
                throw SeasonCandidateDiscoveryError.failed(message: message)
            }
            return Self.result(
                brandID: brandID,
                jobID: jobID,
                data: data,
                generation: generation,
                sourceURL: sourceURL
            )
        }
        throw CancellationError()
    }

    func observeLatestSeasonDiscovery(
        brandID: BrandID
    ) -> AsyncThrowingStream<SeasonCandidateDiscoveryResult?, Error> {
        AsyncThrowingStream { continuation in
            let listener = db
                .collection("brands").document(brandID.value)
                .collection("seasonDiscoveryJobs")
                .order(by: "createdAt", descending: true)
                .limit(to: 1)
                .addSnapshotListener { snapshot, error in
                    if let error {
                        continuation.finish(throwing: error)
                        return
                    }
                    guard let document = snapshot?.documents.first else {
                        continuation.yield(nil)
                        return
                    }
                    continuation.yield(Self.result(
                        brandID: brandID,
                        jobID: document.documentID,
                        data: document.data()
                    ))
                }
            continuation.onTermination = { _ in listener.remove() }
        }
    }

    func retrySeasonDiscovery(brandID: BrandID, jobID: String) async throws {
        _ = try await transport.call(
            "retrySeasonDiscovery",
            data: ["brandID": brandID.value, "jobID": jobID]
        )
    }

    func cancelSeasonDiscovery(brandID: BrandID, jobID: String) async throws {
        _ = try await transport.call(
            "cancelSeasonDiscovery",
            data: ["brandID": brandID.value, "jobID": jobID]
        )
    }

    func retrySeasonDiscoveryAfterExtractionFix(
        brandID: BrandID,
        job: SeasonCandidateDiscoveryResult
    ) async throws -> SeasonCandidateDiscoveryResult {
        let response = try await transport.call(
            "retrySeasonDiscoveryAfterExtractionFix",
            data: try mutationPayload(brandID: brandID, job: job)
        )
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        return SeasonCandidateDiscoveryResult(
            brandID: brandID,
            jobID: try decoder.string("jobID"),
            generation: try decoder.int("generation"),
            status: .queued,
            sourceURL: try decoder.string("sourceArchiveURL"),
            candidateCount: 0,
            candidateSnapshotHash: nil,
            requestedAt: Date()
        )
    }

    func fetchReviewCandidates(
        brandID: BrandID,
        jobID: String
    ) async throws -> [SeasonDiscoveryReviewCandidate] {
        let snapshot = try await db
            .collection("brands").document(brandID.value)
            .collection("seasonDiscoveryJobs").document(jobID)
            .collection("candidates")
            .whereField("resolution", in: [
                "awaitingReviewAmbiguousTitle",
                "awaitingReviewConflictingMatch",
                "awaitingReviewDuplicateConvergence"
            ])
            .order(by: "sortIndex")
            .getDocuments()
        return snapshot.documents.map { document in
            let data = document.data()
            return SeasonDiscoveryReviewCandidate(
                id: document.documentID,
                title: data["title"] as? String ?? "이름 없는 시즌",
                seasonURL: data["seasonURL"] as? String ?? "",
                coverImageURL: data["coverImageURL"] as? String,
                resolution: data["resolution"] as? String ?? "",
                matchedSeasonID: (data["matchedSeasonID"] as? String).map {
                    SeasonID(value: $0)
                }
            )
        }
    }

    func resolveReviewCandidate(
        brandID: BrandID,
        job: SeasonCandidateDiscoveryResult,
        candidateID: String,
        decision: String,
        targetSeasonID: SeasonID?
    ) async throws {
        guard let snapshotHash = job.candidateSnapshotHash else {
            throw SeasonCandidateDiscoveryError.failed(
                message: "검토할 시즌 목록의 식별 정보가 없습니다."
            )
        }
        var data: [String: Any] = [
            "brandID": brandID.value,
            "jobID": job.jobID,
            "candidateID": candidateID,
            "generation": job.generation,
            "candidateSnapshotHash": snapshotHash,
            "decision": decision
        ]
        if let targetSeasonID {
            data["targetSeasonID"] = targetSeasonID.value
        }
        _ = try await transport.call("resolveSeasonDiscoveryCandidate", data: data)
    }

    private static func jobStream(
        db: Firestore,
        brandID: BrandID,
        jobID: String
    ) -> AsyncThrowingStream<[String: Any], Error> {
        AsyncThrowingStream { continuation in
            let listener = db.collection("brands").document(brandID.value)
                .collection("seasonDiscoveryJobs").document(jobID)
                .addSnapshotListener { snapshot, error in
                    if let error {
                        continuation.finish(throwing: error)
                    } else if let data = snapshot?.data() {
                        continuation.yield(data)
                    }
                }
            continuation.onTermination = { _ in listener.remove() }
        }
    }

    private static func result(
        brandID: BrandID,
        jobID: String,
        data: [String: Any],
        generation: Int? = nil,
        sourceURL: String? = nil
    ) -> SeasonCandidateDiscoveryResult {
        let rawStatus = data["status"] as? String ?? "unknown"
        return SeasonCandidateDiscoveryResult(
            brandID: brandID,
            jobID: jobID,
            generation: generation ?? data["generation"] as? Int ?? 0,
            status: SeasonDiscoveryJobStatus(rawValue: rawStatus) ?? .unknown,
            sourceURL: sourceURL ?? data["sourceArchiveURL"] as? String ?? "",
            candidateCount: data["candidateCount"] as? Int ?? 0,
            candidateSnapshotHash: data["candidateSnapshotHash"] as? String,
            newSeasonCandidateCount: data["newSeasonCandidateCount"] as? Int ?? 0,
            reviewCandidateCount: data["reviewCandidateCount"] as? Int ?? 0,
            matchedCandidateCount: data["matchedCandidateCount"] as? Int ?? 0,
            phase: data["phase"] as? String,
            errorMessage: data["errorMessage"] as? String,
            retryable: data["retryable"] as? Bool ?? false,
            recommendedAction: data["recommendedAction"] as? String ?? "none",
            extractionIssueStatus: (data["extractionIssueStatus"] as? String)
                .flatMap(ExtractionIssueStatus.init(rawValue:)),
            retryAvailableRuntimeVersion:
                data["retryAvailableRuntimeVersion"] as? String,
            extractionIssueWontFixReason:
                data["extractionIssueWontFixReason"] as? String,
            requestedAt: (data["lastRequestedAt"] as? Timestamp)?.dateValue(),
            completedAt: (data["completedAt"] as? Timestamp)?.dateValue()
        )
    }

    private func mutationPayload(
        brandID: BrandID,
        job: SeasonCandidateDiscoveryResult
    ) throws -> [String: Any] {
        guard let snapshotHash = job.candidateSnapshotHash else {
            throw SeasonCandidateDiscoveryError.failed(
                message: "다시 가져올 시즌 목록의 식별 정보가 없습니다."
            )
        }
        return [
            "brandID": brandID.value,
            "jobID": job.jobID,
            "generation": job.generation,
            "candidateSnapshotHash": snapshotHash
        ]
    }
}
