import Foundation
import Testing
@testable import OutPick

struct StartSeasonImportExtractionUseCaseTests {
    @Test
    func persistsBeforeSendingAndReusesSameEnvelopeAfterUncertainResponse() async throws {
        let store = GRDBLookbookImportRequestStore(database: try TemporaryAppDatabase.make())
        let repository = SeasonImportQueueRepositorySpy(store: store, failuresBeforeReceipt: 1)
        let useCase = StartSeasonImportExtractionUseCase(
            importJobRequestingRepository: repository,
            requestStore: store,
            ownerUIDProvider: { "user-a" },
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        do {
            _ = try await useCase.execute(brandID: BrandID(value: "brand-1"), candidates: [candidate()])
            Issue.record("첫 응답은 유실되어야 합니다.")
        } catch SeasonImportQueueRepositorySpyError.responseLost {
            // 응답이 유실된 요청은 같은 로컬 ID로 복구한다.
        }

        let receipt = try await useCase.execute(
            brandID: BrandID(value: "brand-1"),
            candidates: [candidate()]
        )
        let sentEnvelopes = await repository.sentEnvelopes
        let sentStates = await repository.localStatesAtSend

        #expect(sentEnvelopes.count == 2)
        #expect(sentEnvelopes[0] == sentEnvelopes[1])
        #expect(sentStates == [.submitting, .submitting])
        #expect(receipt.requestID == sentEnvelopes[0].requestID)

        _ = try await useCase.execute(brandID: BrandID(value: "brand-1"), candidates: [candidate()])
        let finalEnvelopeCount = await repository.sentEnvelopes.count
        #expect(finalEnvelopeCount == 2)
    }

    private func candidate() -> SeasonCandidate {
        SeasonCandidate(
            id: "candidate-1",
            brandID: BrandID(value: "brand-1"),
            title: "2026 SS",
            seasonURL: "https://example.com/2026ss",
            coverImageURL: nil,
            sourceArchiveURL: "https://example.com/collections",
            extractionScore: 1,
            sortIndex: 0,
            status: "ready",
            discoveryJobID: "discovery-1",
            discoveryGeneration: 1,
            candidateSnapshotHash: "snapshot-1",
            resolution: "newSeason",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private enum SeasonImportQueueRepositorySpyError: Error {
    case responseLost
    case receiptUnavailable
}

private actor SeasonImportQueueRepositorySpy: SeasonImportJobRequestingRepositoryProtocol {
    private let store: any LookbookImportRequestStoringRepositoryProtocol
    private var failuresBeforeReceipt: Int
    private var receipt: LookbookImportQueueReceipt?
    private(set) var sentEnvelopes: [LookbookImportQueueContract.RequestEnvelope] = []
    private(set) var localStatesAtSend: [LookbookImportRequest.LocalState] = []

    init(
        store: any LookbookImportRequestStoringRepositoryProtocol,
        failuresBeforeReceipt: Int
    ) {
        self.store = store
        self.failuresBeforeReceipt = failuresBeforeReceipt
    }

    func requestSeasonCandidateImportJobs(
        brandID: BrandID,
        discoveryJobID: String,
        generation: Int,
        candidateIDs: [String],
        candidateSnapshotHash: String,
        envelope: LookbookImportQueueContract.RequestEnvelope
    ) async throws -> LookbookImportQueueReceipt {
        sentEnvelopes.append(envelope)
        let requests = try await store.fetchUnsettled(ownerUID: "user-a", brandID: brandID.value)
        localStatesAtSend.append(requests.first(where: { $0.requestID == envelope.requestID })?.localState ?? .prepared)
        if failuresBeforeReceipt > 0 {
            failuresBeforeReceipt -= 1
            throw SeasonImportQueueRepositorySpyError.responseLost
        }
        let result = makeReceipt(brandID: brandID.value, envelope: envelope, candidateIDs: candidateIDs)
        receipt = result
        return result
    }

    func getSeasonImportBatch(requestID: String) async throws -> LookbookImportQueueReceipt {
        guard let receipt, receipt.requestID == requestID else {
            throw SeasonImportQueueRepositorySpyError.receiptUnavailable
        }
        return receipt
    }

    private func makeReceipt(
        brandID: String,
        envelope: LookbookImportQueueContract.RequestEnvelope,
        candidateIDs: [String]
    ) -> LookbookImportQueueReceipt {
        LookbookImportQueueReceipt(
            contractVersion: 1,
            requestID: envelope.requestID,
            batchID: String(repeating: "a", count: 64),
            brandID: brandID,
            kind: "importSeasons",
            state: .queued,
            stateRevision: 1,
            items: candidateIDs.enumerated().map { index, candidateID in
                LookbookImportQueueReceipt.Item(
                    itemID: "item-\(index)",
                    targetID: candidateID,
                    ordinal: index,
                    admissionStatus: "created",
                    processingStatus: "queued",
                    jobID: "job-\(index)",
                    executionID: "execution-\(index)",
                    errorCode: nil
                )
            }
        )
    }
}
