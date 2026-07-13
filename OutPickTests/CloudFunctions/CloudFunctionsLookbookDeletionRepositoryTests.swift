import Foundation
import Testing
@testable import OutPick

struct CloudFunctionsLookbookDeletionRepositoryTests {
    @Test func coversDeletionCallableContracts() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [
            Self.mutation(), Self.mutation(), Self.mutation(), Self.batch(targetType: "season"),
            Self.mutation(), Self.mutation(), Self.batch(targetType: "post"), Self.mutation(),
            ["requests": [], "nextCursor": ["updatedAt": "2026-07-13", "requestID": "request-1"]],
            ["requestID": "request-1", "manualRetryState": "queued", "duplicate": false]
        ]
        let repository = CloudFunctionsLookbookDeletionRepository(transport: transport)
        let brandID = BrandID(value: "brand-1")
        let seasonID = SeasonID(value: "season-1")
        let postID = PostID(value: "post-1")

        _ = try await repository.requestBrandDeletion(brandID: brandID, reason: "reason")
        _ = try await repository.cancelBrandDeletion(brandID: brandID)
        _ = try await repository.softDeleteSeason(
            brandID: brandID, seasonID: seasonID, reason: nil
        )
        _ = try await repository.batchSoftDeleteSeasons(
            brandID: brandID, seasonIDs: [seasonID], reason: "reason"
        )
        _ = try await repository.restoreSeason(brandID: brandID, seasonID: seasonID)
        _ = try await repository.softDeletePost(
            brandID: brandID, seasonID: seasonID, postID: postID, reason: nil
        )
        _ = try await repository.batchSoftDeletePosts(
            brandID: brandID, seasonID: seasonID, postIDs: [postID], reason: "reason"
        )
        _ = try await repository.restorePost(
            brandID: brandID, seasonID: seasonID, postID: postID
        )
        let page = try await repository.listDeletionRequests(
            targetType: .post,
            brandID: brandID,
            limit: 20,
            cursor: .init(updatedAt: "cursor-date", requestID: "cursor-id")
        )
        _ = try await repository.retryFailedPurge(requestID: "request-1")

        #expect(transport.calls.map(\.name) == [
            "requestBrandDeletion", "cancelBrandDeletion", "softDeleteSeason",
            "batchSoftDeleteSeasons", "restoreSeason", "softDeletePost",
            "batchSoftDeletePosts", "restorePost", "listLookbookDeletionRequests",
            "retryFailedLookbookDeletionPurge"
        ])
        #expect(transport.calls[2].data["reason"] == nil)
        #expect(transport.calls[8].data["cursorRequestID"] as? String == "cursor-id")
        #expect(page.nextCursor?.requestID == "request-1")
    }

    private static func mutation() -> [String: Any] {
        ["brandID": "brand-1", "status": "active"]
    }

    private static func batch(targetType: String) -> [String: Any] {
        [
            "brandID": "brand-1", "targetType": targetType, "requestedCount": 1,
            "succeededCount": 1, "failedCount": 0,
            "results": [[
                "success": true, "targetType": targetType, "targetID": "target-1",
                "brandID": "brand-1"
            ]]
        ]
    }
}
