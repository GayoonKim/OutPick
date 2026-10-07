import Foundation
import CryptoKit

// 서버 실행 정책과 앱의 공통 접수/영수증 검증 경계다.
enum LookbookImportQueueContract {
    static let version = 1
    static let policy: [String: Int64] = [
        "maxSelectedSeasons": 80,
        "seasonConcurrency": 6,
        "downloadConcurrency": 4,
        "transformConcurrency": 1,
        "uploadConcurrency": 4,
        "sourceReuseBytes": 134217728,
        "browserConcurrency": 1,
        "stopAdmissionAfterMs": 720000,
        "drainTargetAfterMs": 840000,
        "externalDeadlineMs": 900000,
        "memoryLimitPercent": 85,
        "memorySustainedMs": 1000,
        "memorySampleMs": 100,
        "memoryMaxGapMs": 500,
        "importAttempts": 5,
        "discoveryAttempts": 3,
        "preparationAttempts": 5,
        "noProgressSegments": 2,
        "processingPollMs": 3000,
        "waitingPollMs": 10000,
        "pollErrorInitialMs": 10000,
        "pollErrorSecondMs": 20000,
        "pollErrorThirdMs": 40000,
        "pollErrorMaxMs": 60000,
        "reconcileIntervalMs": 300000,
        "fileCleanupIntervalMs": 3600000,
        "recordCleanupIntervalMs": 86400000,
        "cleanupPageSize": 100,
        "cleanupMaxPages": 5,
        "cleanupMaxOperations": 500,
        "cleanupAdmissionMs": 120000,
        "newRequestMaxAgeMs": 86400000,
        "newRequestMaxFutureMs": 300000,
        "unreferencedFileRetentionMs": 86400000,
        "successDetailRetentionMs": 86400000,
        "receiptRetentionMs": 2592000000,
        "resolvedFailureRetentionMs": 2592000000,
        "recoveryAuditRetentionMs": 7776000000,
        "localSettledRetentionMs": 2592000000
    ]
    static let admissionStatuses = ["pending", "created", "duplicate", "failed", "skipped"]
    static let errorCodes = [
        "INVALID_CONTRACT",
        "REQUEST_EXPIRED",
        "CLOCK_INVALID",
        "REQUEST_ID_CONFLICT",
        "SNAPSHOT_STALE",
        "PERMISSION_DENIED",
        "TARGET_DELETED"
    ]

    enum BatchState: String, Codable, CaseIterable {
        case preparing, queued, active, draining, retryWaiting, recoveryRequired, released
    }

    enum ContractError: String, Error {
        case invalidContract = "INVALID_CONTRACT"
        case requestExpired = "REQUEST_EXPIRED"
        case clockInvalid = "CLOCK_INVALID"
    }

    struct RequestEnvelope: Codable, Equatable {
        let queueContractVersion: Int
        let requestID: String
        let requestCreatedAt: Int64
    }

    static func makeRequestEnvelope(
        requestID: UUID = UUID(),
        now: Date = Date()
    ) -> RequestEnvelope {
        RequestEnvelope(
            queueContractVersion: version,
            requestID: requestID.uuidString.lowercased(),
            requestCreatedAt: Int64((now.timeIntervalSince1970 * 1_000).rounded(.down))
        )
    }

    static func receiptMatches(
        _ receipt: LookbookImportQueueReceipt,
        request: RequestEnvelope,
        brandID: String,
        kind: String
    ) -> Bool {
        receipt.contractVersion == request.queueContractVersion &&
            receipt.requestID == request.requestID &&
            receipt.brandID == brandID &&
            receipt.kind == kind
    }

    static func deterministicJobID(batchID: String, itemID: String) -> String {
        let payload = [batchID, itemID, "job"]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed])) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func decodeEnvelope(_ data: Data) throws -> RequestEnvelope {
        guard let value = try? JSONDecoder().decode(RequestEnvelope.self, from: data),
              value.queueContractVersion == version,
              value.requestID.utf8.count == 36,
              value.requestID.range(
                of: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
                options: .regularExpression
              ) != nil,
              value.requestCreatedAt >= 0,
              value.requestCreatedAt <= 9_007_199_254_740_991 else {
            throw ContractError.invalidContract
        }
        return value
    }

    // 서버가 기존 영수증을 확인한 뒤 신규 접수에만 적용할 시간 경계다.
    static func newAdmissionTimeError(createdAt: Int64, now: Int64) throws -> ContractError? {
        guard (0...9_007_199_254_740_991).contains(createdAt),
              (0...9_007_199_254_740_991).contains(now) else {
            throw ContractError.invalidContract
        }
        if now - createdAt > policy["newRequestMaxAgeMs"]! { return .requestExpired }
        if createdAt - now > policy["newRequestMaxFutureMs"]! { return .clockInvalid }
        return nil
    }
}
