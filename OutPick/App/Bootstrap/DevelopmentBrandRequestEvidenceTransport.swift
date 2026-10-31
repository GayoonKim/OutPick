#if DEBUG
import Foundation
import CoreFoundation
import FirebaseFunctions

/// 정상 Development 인증/호출은 그대로 두고 공개 요청의 허용 항목만 관측한다.
final class DevelopmentBrandRequestEvidenceTransport: CloudFunctionsTransporting {
    private let base: any CloudFunctionsTransporting
    private let store: DevelopmentBrandRequestEvidenceStore

    init(base: any CloudFunctionsTransporting, store: DevelopmentBrandRequestEvidenceStore) {
        self.base = base
        self.store = store
    }

    static func isEnabled(arguments: [String], environment: [String: String],
                          info: [String: Any], bundleID: String?, localMode: Bool) -> Bool {
        arguments.contains("-BrandRequestSDKQA") && environment["UITESTS"] != "1" && !localMode
            && info["OUTPICK_ENVIRONMENT"] as? String == "development"
            && info["OUTPICK_EXPECTED_FIREBASE_PROJECT_ID"] as? String == "outpick-test"
            && bundleID == "GayoonKim.OutPick.dev"
    }

    static func makeIfEnabled(base: any CloudFunctionsTransporting) -> (any CloudFunctionsTransporting)? {
        #if OUTPICK_BRAND_LOCAL_INTEGRATION || OUTPICK_BRAND_LOCAL_DEVICE
        let localMode = true
        #else
        let localMode = false
        #endif
        guard isEnabled(arguments: ProcessInfo.processInfo.arguments,
                        environment: ProcessInfo.processInfo.environment,
                        info: Bundle.main.infoDictionary ?? [:],
                        bundleID: Bundle.main.bundleIdentifier, localMode: localMode) else { return nil }
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("[BrandRequestSDKQA] evidence directory unavailable")
            return nil
        }
        let directory = support.appendingPathComponent("BrandRequestSDKQA", isDirectory: true)
        let sessionID = UUID().uuidString
        let store = DevelopmentBrandRequestEvidenceStore(
            sessionID: sessionID, fileURL: directory.appendingPathComponent("\(sessionID).json"))
        print("[BrandRequestSDKQA] session \(sessionID)")
        return DevelopmentBrandRequestEvidenceTransport(base: base, store: store)
    }

    func call(_ name: String, data: [String: Any]) async throws -> [String: Any] {
        guard ["submitBrandRequest", "listMyBrandRequests"].contains(name) else {
            return try await base.call(name, data: data)
        }
        let callID = UUID().uuidString
        store.record(call: name, callID: callID, event: "started", fields: [:])
        do {
            let response = try await base.call(name, data: data)
            var fields = DevelopmentBrandRequestEvidenceStore.response(response, call: name)
            fields["strictMapperCheckPassed"] = Self.mapperAccepts(response, call: name, input: data)
            store.record(call: name, callID: callID, event: "returned",
                         fields: fields)
            return response
        } catch {
            store.record(call: name, callID: callID, event: "failed",
                         fields: DevelopmentBrandRequestEvidenceStore.failure(error))
            throw error
        }
    }

    private static func mapperAccepts(_ response: [String: Any], call: String, input: [String: Any]) -> Bool {
        do {
            if call == "submitBrandRequest" {
                _ = try BrandRequestCloudFunctionsMapper.submissionReceipt(response)
            } else {
                guard let raw = input["scope"] as? String, let scope = BrandRequestListScope(rawValue: raw) else {
                    return false
                }
                _ = try BrandRequestCloudFunctionsMapper.historyPage(response, scope: scope)
            }
            return true
        } catch { return false }
    }
}

final class DevelopmentBrandRequestEvidenceStore: @unchecked Sendable {
    private let lock = NSLock()
    private let sessionID: String
    private let write: (Data) throws -> Void
    private var events: [[String: Any]] = []
    private var writeFailures = 0

    init(sessionID: String = UUID().uuidString, write: @escaping (Data) throws -> Void) {
        self.sessionID = sessionID
        self.write = write
    }

    convenience init(sessionID: String, fileURL: URL) {
        self.init(sessionID: sessionID) { data in
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            var excludedDirectory = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try excludedDirectory.setResourceValues(values)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }
    }

    func record(call: String, callID: String, event: String, fields: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        events.append(["sequence": events.count + 1, "at": formatter.string(from: Date()),
                       "call": call, "callID": callID, "event": event, "fields": fields])
        do {
            let data = try JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1, "sessionID": sessionID, "projectID": "outpick-test",
                "region": "asia-northeast3", "writeFailures": writeFailures, "events": events
            ], options: [.prettyPrinted, .sortedKeys])
            try write(data)
        } catch {
            writeFailures += 1
            // 오류 원문에는 경로/인증정보가 섞일 수 있어 출력하지 않는다.
            print("[BrandRequestSDKQA] evidence write failed")
        }
    }

    static func response(_ raw: [String: Any], call: String) -> [String: Any] {
        if call == "submitBrandRequest" {
            return project(raw, keys: ["requestID", "groupID", "status", "isDuplicate",
                                       "remainingToday", "resolvedBrandID"])
        }
        var value = project(raw, keys: ["scope"])
        if let rows = raw["requests"] as? [[String: Any]] {
            value["requests"] = rows.map { project($0, keys: ["requestID", "groupID", "status",
                "resolvedBrandID", "rejectionReason", "createdAt", "updatedAt"]) }
        } else if raw["requests"] != nil {
            value["requestsInvalid"] = true
        }
        if raw["nextCursor"] is NSNull { value["nextCursor"] = NSNull() }
        else if let cursor = raw["nextCursor"] as? [String: Any] {
            value["nextCursor"] = project(cursor, keys: ["createdAt", "requestID"])
        } else if raw["nextCursor"] != nil { value["nextCursorInvalid"] = true }
        return value
    }

    private static func project(_ raw: [String: Any], keys: [String]) -> [String: Any] {
        var result: [String: Any] = [:]
        var invalid: [String] = []
        for key in keys {
            guard let value = raw[key] else { continue }
            if value is NSNull, ["resolvedBrandID", "rejectionReason"].contains(key) {
                result[key] = NSNull()
            } else if let string = value as? String, allowed(string, key: key) {
                result[key] = string
            } else if let number = value as? NSNumber {
                let boolean = CFGetTypeID(number) == CFBooleanGetTypeID()
                if key == "isDuplicate" && boolean { result[key] = number }
                else if key == "remainingToday" && !boolean && number.doubleValue.isFinite
                    && number.doubleValue.rounded() == number.doubleValue
                    && (0...5).contains(number.doubleValue) { result[key] = number }
                else { invalid.append(key) }
            } else { invalid.append(key) }
        }
        if !invalid.isEmpty { result["invalidFields"] = invalid }
        return result
    }

    private static func allowed(_ string: String, key: String) -> Bool {
        switch key {
        case "requestID", "groupID", "resolvedBrandID":
            return string.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil
        case "status": return BrandRequestStatus(rawValue: string) != nil
        case "scope": return BrandRequestListScope(rawValue: string) != nil
        case "rejectionReason":
            return ["공식 룩북 확인 필요", "이용 허락 확인 필요", "브랜드 정보 확인 필요", "기타"].contains(string)
        case "createdAt", "updatedAt":
            return string.range(of: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$", options: .regularExpression) != nil
        default: return false
        }
    }

    static func failure(_ error: Error) -> [String: Any] {
        let error = error as NSError
        let domain = [FunctionsErrorDomain, NSURLErrorDomain].contains(error.domain) ? error.domain : "other"
        var result: [String: Any] = ["domain": domain, "code": error.code]
        if error.domain == FunctionsErrorDomain,
           let reason = (error.userInfo[FunctionsErrorDetailsKey] as? [String: Any])?["reason"] as? String,
           ["DAILY_LIMIT_REACHED", "QUERY_BUDGET_EXCEEDED", "REQUEST_BLOCKED", "INVALID_CURSOR",
            "INVALID_INPUT", "DATA_INVALID"].contains(reason) { result["reason"] = reason }
        return result
    }
}
#endif
