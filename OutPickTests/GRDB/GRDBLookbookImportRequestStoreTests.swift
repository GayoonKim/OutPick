import Foundation
import Testing
@testable import OutPick

struct GRDBLookbookImportRequestStoreTests {
    @Test
    func samePendingPayloadReusesSameIdentityButOtherAccountsStayIsolated() async throws {
        let store = GRDBLookbookImportRequestStore(database: try TemporaryAppDatabase.make())
        let first = request(ownerUID: "user-a", requestID: "request-a", now: 1_000)

        let inserted = try await store.prepareOrReuse(first)
        let reused = try await store.prepareOrReuse(
            request(ownerUID: "user-a", requestID: "request-b", now: 2_000)
        )
        let isolated = try await store.prepareOrReuse(
            request(ownerUID: "user-b", requestID: "request-c", now: 2_000)
        )

        #expect(inserted.didReuse == false)
        #expect(reused.didReuse)
        #expect(reused.request.requestID == first.requestID)
        #expect(isolated.didReuse == false)
        #expect(isolated.request.ownerUID == "user-b")
    }

    @Test
    func onlySettledRecordsExpireAndUnresolvedRecordsRemain() async throws {
        let store = GRDBLookbookImportRequestStore(database: try TemporaryAppDatabase.make())
        let settled = request(ownerUID: "user-a", requestID: "settled", now: 1)
        let unresolved = request(
            ownerUID: "user-a",
            requestID: "unresolved",
            now: 1,
            payloadDigest: "different-payload"
        )
        _ = try await store.prepareOrReuse(settled)
        _ = try await store.prepareOrReuse(unresolved)

        var updatedSettled = settled
        updatedSettled.localState = .settled
        updatedSettled.settledAt = 2
        updatedSettled.expiresAt = 10
        updatedSettled.updatedAt = 2
        try await store.update(updatedSettled)

        #expect(try await store.deleteExpiredSettled(now: 10, limit: 10) == 1)
        let remaining = try await store.fetchUnsettled(ownerUID: "user-a", brandID: "brand-1")
        #expect(remaining.map(\.requestID) == ["unresolved"])
    }

    private func request(
        ownerUID: String,
        requestID: String,
        now: Int64,
        payloadDigest: String = "same-payload"
    ) -> LookbookImportRequest {
        LookbookImportRequest(
            ownerUID: ownerUID,
            requestID: requestID,
            contractVersion: 1,
            brandID: "brand-1",
            kind: "importSeasons",
            inputJSON: "{\"candidateIDs\":[\"candidate-1\"]}",
            payloadDigest: payloadDigest,
            localState: .needsReconcile,
            batchID: nil,
            receiptJSON: nil,
            stateRevision: nil,
            createdAt: now,
            updatedAt: now,
            settledAt: nil,
            expiresAt: nil
        )
    }
}
