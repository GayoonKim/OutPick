import Foundation
import Testing
@testable import OutPick

struct CloudFunctionsBrandRequestRepositoryTests {
    @Test func coversBrandRequestCallableContracts() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [
            [
                "requestID": "request-1", "groupID": "group-1",
                "status": "submitted", "isDuplicate": false, "remainingToday": 4,
                "resolvedBrandID": NSNull()
            ],
            [
                "requests": [Self.requestDictionary],
                "nextCursor": ["createdAt": "2026-07-13T00:00:00.000Z", "requestID": "request-1"],
                "scope": "active"
            ],
        ]
        let repository = CloudFunctionsBrandRequestRepository(transport: transport)

        _ = try await repository.submitBrandRequest(
            brandName: "Brand",
            websiteURL: "https://brand.example",
            englishBrandName: nil
        )
        _ = try await repository.listMyBrandRequests(
            scope: .active,
            limit: 10,
            cursor: .init(createdAt: "cursor-date", requestID: "cursor-request")
        )
        #expect(transport.calls.map(\.name) == ["submitBrandRequest", "listMyBrandRequests"])
        #expect(transport.calls[0].data["englishBrandName"] == nil)
        #expect(transport.calls[0].data["websiteURL"] as? String == "https://brand.example")
        #expect(transport.calls[1].data["cursorCreatedAt"] as? String == "cursor-date")

    }

    private static var requestDictionary: [String: Any] {
        ["requestID": "request-1", "groupID": "group-1", "brandName": "Brand", "englishBrandName": NSNull(),
         "websiteURL": "https://brand.example/", "status": "submitted", "resolvedBrandID": NSNull(),
         "rejectionReason": NSNull(), "createdAt": "2026-07-13T00:00:00.000Z", "updatedAt": "2026-07-13T00:00:00.000Z"]
    }

}
