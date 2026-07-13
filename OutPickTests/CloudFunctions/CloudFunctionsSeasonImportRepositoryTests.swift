import Foundation
import Testing
@testable import OutPick

struct CloudFunctionsSeasonImportRepositoryTests {
    @Test func coversSeasonImportCallableContracts() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [
            ["jobID": "job-1", "status": "queued", "seasonURL": "https://season.example.com"],
            [
                "brandID": "brand-1", "candidateIDs": ["candidate-1"], "jobIDs": ["job-2"],
                "requestedJobCount": 1, "failedJobCount": 0, "skippedJobCount": 0
            ],
            ["sourceImportJobID": "job-1", "seasonID": "season-1", "status": "queued"],
            [
                "diagnostic": [
                    "id": "diagnostic-1", "brandID": "brand-1", "type": "season_discovery",
                    "status": "passed", "sourceURL": "https://archive.example.com",
                    "seasonDiscovery": ["storedCandidateCount": 4]
                ]
            ]
        ]
        let brandID = BrandID(value: "brand-1")
        let importing = CloudFunctionsSeasonImportRepository(transport: transport)
        let jobs = CloudFunctionsSeasonImportJobRequestingRepository(transport: transport)
        let retry = CloudFunctionsSeasonAssetRetryRepository(transport: transport)
        let discovery = CloudFunctionsSeasonCandidateDiscoveryRepository(transport: transport)

        _ = try await importing.requestSeasonImport(
            brandID: brandID,
            seasonURL: "https://season.example.com",
            sourceCandidateID: nil
        )
        let batch = try await jobs.requestSeasonCandidateImportJobs(
            brandID: brandID,
            candidateIDs: ["candidate-1"]
        )
        _ = try await retry.requestAssetRetry(brandID: brandID, sourceJobID: "job-1")
        let result = try await discovery.discoverSeasonCandidates(brandID: brandID)

        #expect(transport.calls.map(\.name) == [
            "requestSeasonImport", "requestSeasonCandidateImportJobs",
            "requestSeasonAssetRetry", "runLookbookExtractionDiagnostic"
        ])
        #expect(transport.calls[0].data["sourceCandidateID"] == nil)
        #expect(transport.calls[3].data["type"] as? String == "season_discovery")
        #expect(batch.requestedImportJobCount == 1)
        #expect(result.candidateCount == 4)
    }
}
