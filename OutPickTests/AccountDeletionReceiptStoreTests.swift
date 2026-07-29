import Foundation
import Testing
@testable import OutPick

struct AccountDeletionReceiptStoreTests {
    @Test
    func keychainRoundTripPreservesOnlyOpaqueRecoveryContract() throws {
        let store = AccountDeletionReceiptStore(
            service: "OutPickTests.AccountDeletion.\(UUID().uuidString)"
        )
        defer { try? store.delete() }
        let receipt = AccountDeletionReceipt(
            requestID: "request-1",
            receiptToken: "opaque-token",
            requestedAt: Date(timeIntervalSince1970: 100),
            cancelableUntil: Date(timeIntervalSince1970: 200),
            provider: .kakao
        )

        try store.save(receipt)

        #expect(try store.load() == receipt)
        try store.delete()
        #expect(try store.load() == nil)
    }
}
