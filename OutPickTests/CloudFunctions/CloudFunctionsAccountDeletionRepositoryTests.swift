import Foundation
import Testing
@testable import OutPick

struct CloudFunctionsAccountDeletionRepositoryTests {
    @Test
    func mapsAllAccountDeletionCallableContracts() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [
            [
                "intentID": "intent-1",
                "nonce": "nonce-1",
                "expiresAt": "2026-07-29T12:10:00.000Z"
            ],
            [
                "accountStatus": "deletionPending",
                "requestID": "request-1",
                "receiptToken": "receipt-1",
                "requestedAt": "2026-07-29T12:00:00.000Z",
                "cancelableUntil": "2026-08-05T12:00:00.000Z"
            ],
            [
                "status": "grace",
                "requestedAt": "2026-07-29T12:00:00.000Z",
                "cancelableUntil": "2026-08-05T12:00:00.000Z",
                "message": "삭제 요청을 취소할 수 있어요"
            ],
            [
                "accountStatus": "active",
                "requestID": "request-1",
                "cancelledAt": "2026-07-30T12:00:00.000Z"
            ]
        ]
        let repository = CloudFunctionsAccountDeletionRepository(transport: transport)

        let intent = try await repository.prepareDeletion()
        let payload = try await repository.requestDeletion(intent: intent)
        let receipt = AccountDeletionReceipt(
            requestID: payload.requestID,
            receiptToken: payload.receiptToken,
            requestedAt: payload.requestedAt,
            cancelableUntil: payload.cancelableUntil,
            provider: .google
        )
        let status = try await repository.loadStatus(receipt: receipt)
        let cancellation = try await repository.cancelDeletion()

        #expect(transport.calls.map(\.name) == [
            "prepareAccountDeletion",
            "requestAccountDeletion",
            "getAccountDeletionStatus",
            "cancelAccountDeletion"
        ])
        #expect(transport.calls[1].data["intentID"] as? String == "intent-1")
        #expect(transport.calls[1].data["nonce"] as? String == "nonce-1")
        #expect(transport.calls[2].data["requestID"] as? String == "request-1")
        #expect(transport.calls[2].data["receiptToken"] as? String == "receipt-1")
        #expect(status.status == .grace)
        #expect(cancellation.requestID == "request-1")
    }

    @Test
    func rejectsRequestResponseThatDidNotEnterDeletionPending() async {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [[
            "accountStatus": "active",
            "requestID": "request-1",
            "receiptToken": "receipt-1",
            "requestedAt": "2026-07-29T12:00:00Z",
            "cancelableUntil": "2026-08-05T12:00:00Z"
        ]]
        let repository = CloudFunctionsAccountDeletionRepository(transport: transport)
        let intent = AccountDeletionIntent(
            intentID: "intent-1",
            nonce: "nonce-1",
            expiresAt: Date()
        )

        await #expect(throws: AccountDeletionClientError.invalidResponse) {
            try await repository.requestDeletion(intent: intent)
        }
    }
}
