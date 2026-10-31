#if DEBUG && targetEnvironment(simulator)
import Foundation
import CryptoKit
import FirebaseCore
import Testing
@testable import OutPick

@MainActor
struct BrandLocalUIPreparationTests {
    @Test func historyFailureEvidenceExcludesCredentialsAndPreservesError() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let spy = CloudFunctionsTransportSpy()
        let marker = "synthetic-private-value-for-diagnostic-test"
        let failure = NSError(domain: "com.firebase.functions", code: 7,
            userInfo: [NSLocalizedDescriptionKey: marker, "token": marker])
        spy.error = failure
        let transport = BrandLocalReadOnlyTransport(base: spy, evidence: BrandLocalUIEvidence(url: url))
        do {
            _ = try await transport.call("listMyBrandRequests", data: ["scope": "history", "token": marker])
            Issue.record("실패를 성공으로 보정했습니다.")
        } catch { #expect(error as NSError === failure) }
        let data = try Data(contentsOf: url)
        #expect(!String(decoding: data, as: UTF8.self).contains(marker))
        let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let events = try #require(document["events"] as? [[String: Any]])
        #expect(events.map { $0["kind"] as? String } == ["callable.started", "callable.failed"])
        #expect(events.last?["domain"] as? String == failure.domain)
        #expect(events.last?["code"] as? Int == 7)
        #expect(spy.calls.count == 1)
    }

    private func deviceConfig(_ patch: [String: Any] = [:], badDigest: Bool = false,
        tlsPatch: [String: Any] = [:], wrongCertificate: Bool = false) throws -> BrandLocalUIConfiguration {
        let round = "49fd2792-eca0-45b8-b711-e72b9124add4"
        let target: [String: Any] = ["projectID": "outpick-test", "region": "asia-northeast3",
            "authHost": "127.0.0.1:19099", "functionsHost": "127.0.0.1:15001", "firestoreHost": "127.0.0.1:18080",
            "allRequiredServicesLocal": true, "inheritedCredentials": false,
            "directory": "/local/" + round, "functionNames": ["submitBrandRequest", "listMyBrandRequests", "searchBrands"]]
        let targetData = try JSONSerialization.data(withJSONObject: target)
        let sha = SHA256.hash(data: targetData).map { String(format: "%02x", $0) }.joined()
        let storage: [String: Any] = ["projectID": "outpick-test", "roundID": round,
            "storageHost": "127.0.0.1:19199", "firestoreHost": "127.0.0.1:18080", "targetSHA256": sha]
        let certificate = Data("공개 인증서 SHA 검증용 가상 바이트, 실제 TLS 검사는 아님".utf8)
        let rootSHA = SHA256.hash(data: certificate).map { String(format: "%02x", $0) }.joined()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var tls: [String: Any] = ["publicRootSHA256": rootSHA, "rootFingerprint256": rootSHA.uppercased(),
            "serverFingerprint256": Array(repeating: "AB", count: 32).joined(separator: ":"),
            "validUntil": formatter.string(from: Date().addingTimeInterval(86400))]
        tls.merge(tlsPatch) { _, next in next }
        var relay: [String: Any] = ["status": "ready", "scope": "ios-single-device-read-relay",
            "projectID": "outpick-test", "region": "asia-northeast3", "tenantID": NSNull(), "timeLimit": NSNull(),
            "allowedPeerIP": "192.168.123.169", "roundID": round, "targetSHA256": sha,
            "userUID": "fixture-user", "groupID": "ba0b02d1d3f1c0a889226d2060165c63",
            "brandID": "668fefda94c3ac1055720b1823256703a38a3966de214f5a7989683c199d189c",
            "seasonID": "local-l159-first-season", "credentialsIncluded": false,
            "automaticallyRestarts": false, "expiresOnUSBDisconnect": false, "stopsOnQAComplete": true,
            "connectionVersion": 2, "functionsBaseURL": "https://192.168.123.110:54752/outpick-test/asia-northeast3",
            "functionsTLS": tls,
            "endpoints": ["auth": "192.168.123.110:54751", "functions": "192.168.123.110:54752",
                "firestore": "192.168.123.110:54753", "storage": "192.168.123.110:54754"]]
        relay.merge(patch) { _, next in next }
        let data = try JSONSerialization.data(withJSONObject: relay)
        return try .init(targetData: targetData, storageData: JSONSerialization.data(withJSONObject: storage),
            deviceData: data, expectedDeviceSHA256: badDigest ? "wrong" : SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            publicRootData: wrongCertificate ? Data("다른 공개 인증서".utf8) : certificate)
    }

    @Test func approvedDeviceRelayMapsFourServicesWithoutChangingLoopbackParser() throws {
        let config = try deviceConfig()
        #expect(config.target.auth.authority == "192.168.123.110:54751")
        #expect(config.storageEndpoint.authority == "192.168.123.110:54754")
        #expect(config.target.functionsBaseURL == "https://192.168.123.110:54752/outpick-test/asia-northeast3")
        #expect(config.publicRootSHA256 != nil)
        #expect(throws: (any Error).self) { try BrandLocalIntegrationTarget.Endpoint("192.168.123.110:54751") }
        #expect(FirebaseApp.app() == nil)
    }

    @Test func deviceHTTPSRejectsVersionBaseOrCertificateMismatch() throws {
        for patch: [String: Any] in [["connectionVersion": 1], ["connectionVersion": NSNull()],
            ["functionsTLS": NSNull()], ["functionsBaseURL": "http://192.168.123.110:54752/outpick-test/asia-northeast3"],
            ["functionsBaseURL": "https://192.168.123.111:54752/outpick-test/asia-northeast3"],
            ["functionsBaseURL": "https://192.168.123.110:54751/outpick-test/asia-northeast3"],
            ["functionsBaseURL": "https://192.168.123.110:54752/other/asia-northeast3"],
            ["functionsBaseURL": "https://192.168.123.110:54752/outpick-test/asia-northeast3/"],
            ["functionsBaseURL": "https://192.168.123.110:54752/outpick-test/asia-northeast3?query=1"]] {
            #expect(throws: (any Error).self) { try deviceConfig(patch) }
        }
        #expect(throws: (any Error).self) { try deviceConfig(wrongCertificate: true) }
        #expect(FirebaseApp.app() == nil)
    }

    @Test func deviceHTTPSRejectsExpiredOrMalformedTLSMetadata() throws {
        for patch: [String: Any] in [["publicRootSHA256": "wrong"], ["rootFingerprint256": "wrong"],
            ["serverFingerprint256": "wrong"], ["validUntil": "2020-01-01T00:00:00.000Z"],
            ["validUntil": "2099-01-01T00:00:00.000Z"], ["validUntil": "invalid"], ["validUntil": NSNull()]] {
            #expect(throws: (any Error).self) { try deviceConfig(tlsPatch: patch) }
        }
        #expect(FirebaseApp.app() == nil)
    }

    @Test func deviceRelayRejectsWrongScopePeerRoundSourceTenantAndDigest() throws {
        for patch: [String: Any] in [["status": "stopped"], ["scope": "other"], ["projectID": "other"],
            ["region": "other"], ["tenantID": "fixture-brand-admins"], ["timeLimit": 1],
            ["allowedPeerIP": "192.168.123.170"], ["roundID": UUID().uuidString], ["targetSHA256": "wrong"],
            ["userUID": "admin"], ["groupID": "other"], ["brandID": "other"], ["seasonID": "other"],
            ["credentialsIncluded": true], ["automaticallyRestarts": true], ["expiresOnUSBDisconnect": true],
            ["stopsOnQAComplete": false]] {
            #expect(throws: (any Error).self) { try deviceConfig(patch) }
        }
        #expect(throws: (any Error).self) { try deviceConfig(badDigest: true) }
        #expect(FirebaseApp.app() == nil)
    }

    @Test func deviceRelayRejectsRemoteLoopbackMalformedAndOverlappingEndpoints() throws {
        let valid = ["auth": "192.168.123.110:54751", "functions": "192.168.123.110:54752",
            "firestore": "192.168.123.110:54753", "storage": "192.168.123.110:54754"]
        for key in valid.keys {
            for address in ["127.0.0.1:54751", "192.168.123.111:54751", "example.com:443", "192.168.123.110:054751",
                "192.168.123.110:65536", "192.168.123.110:0", "https://192.168.123.110:54751"] {
                var endpoints = valid
                endpoints[key] = address
                #expect(throws: (any Error).self) { try deviceConfig(["endpoints": endpoints]) }
            }
        }
        #expect(throws: (any Error).self) { try deviceConfig(["endpoints": ["auth": valid["auth"]!]]) }
        var overlapping = valid
        overlapping["storage"] = valid["auth"]
        #expect(throws: (any Error).self) { try deviceConfig(["endpoints": overlapping]) }
        #expect(FirebaseApp.app() == nil)
    }

    @Test func unregisteredEnvironmentStopsBeforeDefaultSDKCreation() {
        #expect(throws: BrandLocalIntegrationError.self) {
            try BrandLocalRepositoryEnvironment().installedProvider()
        }
        #expect(FirebaseApp.app() == nil)
    }

    private func config(_ patch: [String: Any] = [:]) throws -> BrandLocalUIConfiguration {
        let target: [String: Any] = ["projectID": "outpick-test", "region": "asia-northeast3",
            "authHost": "127.0.0.1:19099", "functionsHost": "127.0.0.1:15001", "firestoreHost": "127.0.0.1:18080",
            "allRequiredServicesLocal": true, "inheritedCredentials": false,
            "directory": "/local/00000000-0000-4000-8000-000000000001",
            "functionNames": ["submitBrandRequest", "listMyBrandRequests", "searchBrands"]]
        let data = try JSONSerialization.data(withJSONObject: target)
        var storage: [String: Any] = ["projectID": "outpick-test", "roundID": "00000000-0000-4000-8000-000000000001",
            "storageHost": "127.0.0.1:19199", "firestoreHost": "127.0.0.1:18080",
            "targetSHA256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]
        storage.merge(patch) { _, next in next }
        return try .init(targetData: data, storageData: JSONSerialization.data(withJSONObject: storage))
    }

    @Test func matchingFourLocalServicesAreAcceptedWithoutSDKCreation() throws {
        let value = try config()
        #expect(value.storageEndpoint.authority == "127.0.0.1:19199")
        #expect(value.target.functionsBaseURL == nil)
        #expect(FirebaseApp.app() == nil)
    }

    @Test func mixedStorageRoundSourceOrRemoteEndpointFailsClosed() throws {
        for patch: [String: Any] in [["projectID": "other"], ["roundID": "old-round"],
            ["targetSHA256": "wrong"], ["firestoreHost": "127.0.0.1:18081"],
            ["storageHost": "storage.googleapis.com:443"], ["storageHost": "127.0.0.1:19099"]] {
            #expect(throws: (any Error).self) { try config(patch) }
        }
        #expect(FirebaseApp.app() == nil)
    }

    @Test func onlyHistoryCallablePassesAndMutationsNeverReachSDK() async throws {
        let spy = CloudFunctionsTransportSpy()
        spy.responses = [["scope": "history", "requests": [], "nextCursor": NSNull()]]
        let readonly = BrandLocalReadOnlyTransport(base: spy)
        for name in ["submitBrandRequest", "createBrand", "setBrandLike", "getBrandAdminCapabilities"] {
            do {
                _ = try await readonly.call(name, data: [:])
                Issue.record("읽기 전용 검사 모드에서 허용하지 않은 호출이 통과했습니다.")
            } catch { #expect(error is BrandLocalIntegrationError) }
        }
        #expect(spy.calls.isEmpty)
        let response = try await readonly.call("listMyBrandRequests", data: ["scope": "history"])
        #expect(response["scope"] as? String == "history")
        #expect(spy.calls.count == 1)
    }

    @Test func historyErrorsAreNotReplacedBySuccessfulEmptyRows() async throws {
        let spy = CloudFunctionsTransportSpy()
        spy.error = BrandRequestFailure.unavailable
        do {
            _ = try await BrandLocalReadOnlyTransport(base: spy).call("listMyBrandRequests", data: [:])
            Issue.record("조회 장애를 정상 빈 목록으로 바꾸었습니다.")
        } catch { #expect(error as? BrandRequestFailure == .unavailable) }
        #expect(spy.calls.count == 1)
    }
}

#endif
