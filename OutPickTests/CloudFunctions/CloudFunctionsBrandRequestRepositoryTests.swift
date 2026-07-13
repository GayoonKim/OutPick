import Foundation
import Testing
@testable import OutPick

struct CloudFunctionsBrandRequestRepositoryTests {
    @Test func coversBrandRequestCallableContracts() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [
            [
                "requestID": "request-1", "groupID": "group-1",
                "status": "submitted", "isDuplicate": false, "remainingToday": 4
            ],
            [
                "requests": [Self.requestDictionary],
                "nextCursor": ["createdAt": "2026-07-13T00:00:00Z", "requestID": "request-1"],
                "scope": "active"
            ],
            [
                "groups": [Self.groupDictionary],
                "nextCursor": ["updatedAt": "2026-07-13T00:00:00Z", "groupID": "group-1"]
            ],
            Self.stageReceipt(status: "submitted", stage: "processing"),
            Self.stageReceipt(status: "added", stage: "completed"),
            Self.stageReceipt(status: "reviewing", stage: "processing")
        ]
        let repository = CloudFunctionsBrandRequestRepository(transport: transport)

        _ = try await repository.submitBrandRequest(
            brandName: "Brand",
            englishBrandName: nil
        )
        _ = try await repository.listMyBrandRequests(
            scope: .active,
            limit: 10,
            cursor: .init(createdAt: "cursor-date", requestID: "cursor-request")
        )
        _ = try await repository.listBrandRequestGroups(
            adminStage: .requested,
            processedScope: .recent,
            limit: 20,
            cursor: .init(updatedAt: "cursor-updated", groupID: "cursor-group")
        )
        _ = try await repository.updateBrandRequestGroupStage(
            groupID: "group-1",
            adminStage: .processing,
            rejectionReason: nil,
            adminNote: "note"
        )
        _ = try await repository.resolveBrandRequestGroup(
            groupID: "group-1",
            resolvedBrandID: BrandID(value: "brand-1"),
            adminNote: nil
        )
        _ = try await repository.markBrandRequestGroupBrandCreated(
            groupID: "group-1",
            createdBrandID: BrandID(value: "brand-1")
        )

        #expect(transport.calls.map(\.name) == [
            "submitBrandRequest", "listMyBrandRequests", "listBrandRequestGroups",
            "updateBrandRequestGroupStage", "resolveBrandRequestGroup",
            "markBrandRequestGroupBrandCreated"
        ])
        #expect(transport.calls[0].data["englishBrandName"] == nil)
        #expect(transport.calls[1].data["cursorCreatedAt"] as? String == "cursor-date")
        #expect(transport.calls[2].data["processedScope"] as? String == "recent")
        #expect(transport.calls[3].data["adminNote"] as? String == "note")
        #expect(transport.calls[3].data["rejectionReason"] == nil)
        #expect(transport.calls[4].data["resolvedBrandID"] as? String == "brand-1")
        #expect(transport.calls[5].data["createdBrandID"] as? String == "brand-1")
    }

    private static var requestDictionary: [String: Any] {
        ["requestID": "request-1", "brandName": "Brand", "status": "submitted"]
    }

    private static var groupDictionary: [String: Any] {
        [
            "groupID": "group-1",
            "displayNameSnapshot": "Brand",
            "adminStage": "requested",
            "status": "submitted"
        ]
    }

    private static func stageReceipt(status: String, stage: String) -> [String: Any] {
        [
            "groupID": "group-1",
            "status": status,
            "adminStage": stage,
            "updatedRequestCount": 1
        ]
    }
}
