#if DEBUG
import Foundation
import FirebaseFunctions
import Testing
@testable import OutPick

@MainActor
struct DevelopmentBrandRequestEvidenceTests {
    @Test func optInRequiresNormalDevelopmentAndRejectsTestsLocalAndProduction() {
        let info: [String: Any] = ["OUTPICK_ENVIRONMENT": "development",
                                  "OUTPICK_EXPECTED_FIREBASE_PROJECT_ID": "outpick-test"]
        func enabled(_ args: [String] = ["-BrandRequestSDKQA"], _ env: [String: String] = [:],
                     _ values: [String: Any]? = nil, _ bundle: String = "GayoonKim.OutPick.dev",
                     _ local: Bool = false) -> Bool {
            DevelopmentBrandRequestEvidenceTransport.isEnabled(arguments: args, environment: env,
                info: values ?? info, bundleID: bundle, localMode: local)
        }
        #expect(enabled())
        #expect(!enabled([]))
        #expect(!enabled(["-BrandRequestSDKQA"], ["UITESTS": "1"]))
        #expect(!enabled(["-BrandRequestSDKQA"], [:], nil, "GayoonKim.OutPick.dev", true))
        #expect(!enabled(["-BrandRequestSDKQA"], [:], [:]))
        #expect(!enabled(["-BrandRequestSDKQA"], [:], info, "GayoonKim.OutPick"))
        #expect(!enabled(["-BrandRequestSDKQA"], [:], ["OUTPICK_ENVIRONMENT": "production",
            "OUTPICK_EXPECTED_FIREBASE_PROJECT_ID": "outpick-664ae"]))
    }

    @Test func receiptObservesSafeFieldsAndForwardsOriginalInputAndResponseOnce() async throws {
        let base = CloudFunctionsTransportSpy()
        var raw = receipt()
        raw["token"] = "PRIVATE_CANARY"
        raw["email"] = "PRIVATE_CANARY@example.invalid"
        base.responses = [raw]
        var writes: [Data] = []
        let store = DevelopmentBrandRequestEvidenceStore { writes.append($0) }
        let observed = DevelopmentBrandRequestEvidenceTransport(base: base, store: store)
        let response = try await observed.call("submitBrandRequest", data: ["brandName": "PRIVATE_CANARY"])
        #expect(base.calls.count == 1 && base.calls[0].data["brandName"] as? String == "PRIVATE_CANARY")
        #expect(response["token"] as? String == "PRIVATE_CANARY")
        #expect(try BrandRequestCloudFunctionsMapper.submissionReceipt(response).groupID == "group-1")
        let output = try #require(writes.last)
        #expect(!String(decoding: output, as: UTF8.self).contains("PRIVATE_CANARY"))
        let recordedEvents = try events(output)
        #expect(recordedEvents.count == 2 && recordedEvents.map { $0["event"] as? String } == ["started", "returned"])
        #expect(recordedEvents[0]["callID"] as? String == recordedEvents[1]["callID"] as? String)
        let fields = try #require(recordedEvents[1]["fields"] as? [String: Any])
        #expect(fields["groupID"] as? String == "group-1" && fields["resolvedBrandID"] is NSNull)
        #expect(fields["strictMapperCheckPassed"] as? Bool == true)
    }

    @Test func damagedReceiptRecordsMapperFailureAndRepositoryStillRejectsWithoutRetry() async throws {
        let base = CloudFunctionsTransportSpy()
        var damaged = receipt()
        damaged.removeValue(forKey: "resolvedBrandID")
        base.responses = [damaged]
        var output = Data()
        let observed = DevelopmentBrandRequestEvidenceTransport(base: base,
            store: DevelopmentBrandRequestEvidenceStore { output = $0 })
        let repository = CloudFunctionsBrandRequestRepository(transport: observed)
        do {
            _ = try await repository.submitBrandRequest(brandName: "모노", websiteURL: "https://mono.example/", englishBrandName: nil)
            Issue.record("손상 응답은 거절해야 합니다.")
        } catch { #expect(error is CloudFunctionsClientError) }
        #expect(base.calls.count == 1)
        let fields = try #require(events(output).last?["fields"] as? [String: Any])
        #expect(fields["strictMapperCheckPassed"] as? Bool == false)
        #expect(fields["resolvedBrandID"] == nil)
    }

    @Test func historyProjectionDistinguishesNullMissingAndDamagedCursorWithoutLeakingNames() throws {
        let row: [String: Any] = ["requestID": "request-1", "groupID": "group-1", "status": "added",
            "resolvedBrandID": "brand-1", "rejectionReason": NSNull(), "brandName": "PRIVATE_CANARY",
            "createdAt": "2026-10-20T01:00:00.000Z", "updatedAt": "2026-10-20T02:00:00.000Z"]
        func project(_ cursor: Any?) -> [String: Any] {
            var raw: [String: Any] = ["scope": "history", "requests": [row]]
            raw["nextCursor"] = cursor
            return DevelopmentBrandRequestEvidenceStore.response(raw, call: "listMyBrandRequests")
        }
        #expect(project(NSNull())["nextCursor"] is NSNull)
        #expect(project(nil)["nextCursor"] == nil && project(nil)["nextCursorInvalid"] == nil)
        #expect(project("PRIVATE_CANARY")["nextCursorInvalid"] as? Bool == true)
        let cursor = project(["createdAt": "2026-10-20T01:00:00.000Z", "requestID": "request-1"])
        #expect((cursor["nextCursor"] as? [String: Any])?["requestID"] as? String == "request-1")
        #expect(!String(decoding: try JSONSerialization.data(withJSONObject: cursor), as: UTF8.self).contains("PRIVATE_CANARY"))
        var damaged = receipt()
        damaged["resolvedBrandID"] = ["PRIVATE_CANARY": "PRIVATE_CANARY"]
        let value = DevelopmentBrandRequestEvidenceStore.response(damaged, call: "submitBrandRequest")
        #expect(value["resolvedBrandID"] == nil)
        #expect(value["invalidFields"] as? [String] == ["resolvedBrandID"])
    }

    @Test func errorsPreserveIdentityAndKnownReasonButExcludeSensitiveDetails() async throws {
        let failure = NSError(domain: FunctionsErrorDomain, code: 8, userInfo: [
            FunctionsErrorDetailsKey: ["reason": "QUERY_BUDGET_EXCEEDED", "token": "PRIVATE_CANARY"],
            NSLocalizedDescriptionKey: "PRIVATE_CANARY"])
        let base = CloudFunctionsTransportSpy()
        base.error = failure
        var output = Data()
        let observed = DevelopmentBrandRequestEvidenceTransport(base: base,
            store: DevelopmentBrandRequestEvidenceStore { output = $0 })
        do { _ = try await observed.call("listMyBrandRequests", data: [:]); Issue.record("오류가 필요합니다.") }
        catch { #expect((error as NSError) === failure) }
        #expect(base.calls.count == 1)
        let fields = try #require(events(output).last?["fields"] as? [String: Any])
        #expect(fields["reason"] as? String == "QUERY_BUDGET_EXCEEDED")
        #expect(!String(decoding: output, as: UTF8.self).contains("PRIVATE_CANARY"))
        let unknown = DevelopmentBrandRequestEvidenceStore.failure(NSError(domain: "PRIVATE_CANARY", code: 9,
            userInfo: [FunctionsErrorDetailsKey: ["reason": "PRIVATE_CANARY"]]))
        #expect(unknown["domain"] as? String == "other" && unknown["reason"] == nil)
    }

    @Test func unrelatedCallsAreNotObservedAndAreForwardedOnce() async throws {
        let base = CloudFunctionsTransportSpy()
        var writes = 0
        let observed = DevelopmentBrandRequestEvidenceTransport(base: base,
            store: DevelopmentBrandRequestEvidenceStore { _ in writes += 1 })
        _ = try await observed.call("unrelatedCall", data: ["token": "PRIVATE_CANARY"])
        #expect(base.calls.count == 1 && writes == 0)
    }

    @Test func evidenceWriteFailureNeverRetriesOrChangesResult() async throws {
        let base = CloudFunctionsTransportSpy()
        base.responses = [receipt()]
        var attempts = 0
        let observed = DevelopmentBrandRequestEvidenceTransport(base: base,
            store: DevelopmentBrandRequestEvidenceStore { _ in
                attempts += 1
                throw CocoaError(.fileWriteNoPermission)
            })
        let result = try await observed.call("submitBrandRequest", data: [:])
        #expect(base.calls.count == 1 && attempts == 2)
        #expect(try BrandRequestCloudFunctionsMapper.submissionReceipt(result).requestID == "request-1")
    }

    @Test func fileEvidenceIsPrivateAndOtherSessionRemainsUnchanged() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.json")
        let second = directory.appendingPathComponent("second.json")
        let a = DevelopmentBrandRequestEvidenceStore(sessionID: "first", fileURL: first)
        a.record(call: "submitBrandRequest", callID: "a", event: "started", fields: [:])
        let original = try Data(contentsOf: first)
        let b = DevelopmentBrandRequestEvidenceStore(sessionID: "second", fileURL: second)
        b.record(call: "listMyBrandRequests", callID: "b", event: "started", fields: [:])
        #expect(try Data(contentsOf: first) == original)
        let attributes = try FileManager.default.attributesOfItem(atPath: second.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func concurrentRecordsHaveUniqueOrderedSequenceAndNoLoss() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("events.json")
        let store = DevelopmentBrandRequestEvidenceStore(sessionID: "concurrent", fileURL: file)
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            store.record(call: "listMyBrandRequests", callID: String(index), event: "started", fields: [:])
        }
        let values = try events(Data(contentsOf: file))
        #expect(values.count == 20)
        #expect(values.compactMap { $0["sequence"] as? Int } == Array(1...20))
        #expect(Set(values.compactMap { $0["callID"] as? String }).count == 20)
    }

    private func receipt() -> [String: Any] {
        ["requestID": "request-1", "groupID": "group-1", "status": "submitted",
         "isDuplicate": false, "remainingToday": 4, "resolvedBrandID": NSNull()]
    }

    private func events(_ data: Data) throws -> [[String: Any]] {
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["events"] as? [[String: Any]])
    }
}
#endif
