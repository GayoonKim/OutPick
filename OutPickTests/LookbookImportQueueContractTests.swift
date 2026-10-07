import Foundation
import Testing
@testable import OutPick

struct LookbookImportQueueContractTests {
    private typealias Contract = LookbookImportQueueContract

    private func fixture() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent(
            "contracts/lookbook-import-queue-v1.json"
        ))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func policyAndStatesMatchSharedFixture() throws {
        let value = try fixture()
        #expect(value["contractVersion"] as? Int == Contract.version)
        let policy = try #require(value["policy"] as? [String: NSNumber])
        #expect(policy.mapValues(\.int64Value) == Contract.policy)
        #expect(value["batchStates"] as? [String] == Contract.BatchState.allCases.map(\.rawValue))
        #expect(value["admissionStatuses"] as? [String] == Contract.admissionStatuses)
        #expect(value["errorCodes"] as? [String] == Contract.errorCodes)
    }

    @Test func envelopeValidatesSharedCases() throws {
        let rows = try #require(fixture()["envelopeCases"] as? [[String: Any]])
        #expect(!rows.isEmpty)
        for row in rows {
            let data = try JSONSerialization.data(
                withJSONObject: #require(row["input"]), options: [.fragmentsAllowed]
            )
            if let error = row["error"] as? String {
                do {
                    _ = try Contract.decodeEnvelope(data)
                    Issue.record("잘못된 계약을 허용함: \(row["name"] ?? "")")
                } catch let actual as Contract.ContractError {
                    #expect(actual.rawValue == error)
                }
            } else {
                let request = try Contract.decodeEnvelope(data)
                let input = try #require(row["input"] as? [String: Any])
                #expect(request.requestID == input["requestID"] as? String)
                #expect(request.requestCreatedAt == (input["requestCreatedAt"] as? NSNumber)?.int64Value)
                #expect(try Contract.decodeEnvelope(JSONEncoder().encode(request)) == request)
            }
        }
    }

    @Test func newAdmissionTimeBoundariesMatchSharedFixture() throws {
        let rows = try #require(fixture()["newAdmissionTimeCases"] as? [[String: Any]])
        #expect(!rows.isEmpty)
        for row in rows {
            let createdAt = try #require(row["requestCreatedAt"] as? NSNumber).int64Value
            let now = try #require(row["now"] as? NSNumber).int64Value
            #expect(try Contract.newAdmissionTimeError(createdAt: createdAt, now: now)?.rawValue
                    == row["error"] as? String)
        }
        #expect(throws: Contract.ContractError.invalidContract) {
            try Contract.newAdmissionTimeError(createdAt: -1, now: 0)
        }
        #expect(throws: Contract.ContractError.invalidContract) {
            try Contract.newAdmissionTimeError(createdAt: 0, now: Int64.max)
        }
    }

    @Test func oldReceiptEnvelopeRemainsDecodable() throws {
        let example = try #require(fixture()["receiptLookupExample"] as? [String: Any])
        let data = try JSONSerialization.data(withJSONObject: #require(example["request"]))
        let request = try Contract.decodeEnvelope(data)
        let now = try #require(example["now"] as? NSNumber).int64Value
        #expect(try Contract.newAdmissionTimeError(createdAt: request.requestCreatedAt, now: now)
                == .requestExpired)
        // 실제 서버 영수증 조회 순서는 Q1, 앱 복원 연결은 Q5에서 검증한다.
    }

    @Test func unknownBatchStateIsRejected() throws {
        for state in Contract.BatchState.allCases {
            #expect(try JSONDecoder().decode(Contract.BatchState.self,
                from: JSONEncoder().encode(state)) == state)
        }
        for state in ["success", "completed", "failed", ""] {
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(Contract.BatchState.self,
                    from: JSONEncoder().encode(state))
            }
        }
    }

    @Test func receiptMustMatchRequestBrandAndQueueKind() {
        let request = Contract.RequestEnvelope(
            queueContractVersion: 1,
            requestID: "123e4567-e89b-42d3-a456-426614174000",
            requestCreatedAt: 1_800_000_000_000
        )
        let receipt = LookbookImportQueueReceipt(
            contractVersion: 1,
            requestID: request.requestID,
            batchID: String(repeating: "a", count: 64),
            brandID: "brand-1",
            kind: "importSeasons",
            state: .queued,
            stateRevision: 1,
            items: []
        )

        #expect(Contract.receiptMatches(receipt, request: request, brandID: "brand-1", kind: "importSeasons"))
        #expect(!Contract.receiptMatches(receipt, request: request, brandID: "brand-2", kind: "importSeasons"))
        #expect(!Contract.receiptMatches(receipt, request: request, brandID: "brand-1", kind: "repair"))
        let otherRequest = Contract.RequestEnvelope(
            queueContractVersion: 1,
            requestID: "223e4567-e89b-42d3-a456-426614174000",
            requestCreatedAt: request.requestCreatedAt
        )
        #expect(!Contract.receiptMatches(receipt, request: otherRequest, brandID: "brand-1", kind: "importSeasons"))
    }
}
