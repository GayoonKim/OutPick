#if DEBUG && targetEnvironment(simulator)
import Foundation
import XCTest
import Testing
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
@testable import OutPick

@MainActor
final class BrandLocalIntegrationPreparationTests: XCTestCase {
    private func target(_ patch: [String: Any] = [:]) throws -> BrandLocalIntegrationTarget {
        var value: [String: Any] = ["projectID": "outpick-test", "region": "asia-northeast3",
            "authHost": "127.0.0.1:19099", "functionsHost": "127.0.0.1:15001", "firestoreHost": "127.0.0.1:18080",
            "allRequiredServicesLocal": true, "inheritedCredentials": false,
            "directory": "/local/00000000-0000-4000-8000-000000000001",
            "functionNames": ["submitBrandRequest", "listMyBrandRequests", "searchBrands"]]
        value.merge(patch) { _, new in new }
        return try .init(data: JSONSerialization.data(withJSONObject: value))
    }

    func testDedicatedModeDoesNotConfigureDefaultFirebaseApp() {
        XCTAssertTrue(BrandLocalIntegrationMode.isEnabled)
        XCTAssertNil(FirebaseApp.app())
    }

    func testOnlyCompleteLocalTargetIsAccepted() throws {
        let value = try target()
        XCTAssertEqual(value.auth.authority, "127.0.0.1:19099")
        XCTAssertEqual(value.functions.authority, "127.0.0.1:15001")
        XCTAssertEqual(value.firestore.authority, "127.0.0.1:18080")
    }

    func testRemoteMixedOrMalformedHostsFailBeforeSDKCreation() {
        for key in ["authHost", "functionsHost", "firestoreHost"] {
            for host in ["outpick-test.firebaseapp.com:443", "https://127.0.0.1:19099", "127.0.0.1:0",
                         "127.0.0.1:65536", "127.0.0.1:19099/path", "localhost:19099"] {
                XCTAssertThrowsError(try target([key: host]))
            }
        }
        XCTAssertNil(FirebaseApp.app())
    }

    func testWrongProjectRegionMissingFunctionsAndSharedPortsFailClosed() {
        for patch: [String: Any] in [["projectID": "other"], ["region": "us-central1"],
            ["allRequiredServicesLocal": false], ["inheritedCredentials": true],
            ["directory": "/local/old"], ["functionNames": []], ["functionsHost": "127.0.0.1:19099"]] {
            XCTAssertThrowsError(try target(patch))
        }
        XCTAssertNil(FirebaseApp.app())
    }
}

#if OUTPICK_BRAND_LOCAL_INTEGRATION
@MainActor
struct BrandLocalSDKIntegrationTests {
    private struct Login: Decodable {
        struct User: Decodable { let uid: String; let email: String }
        let projectID: String
        let syntheticLocalOnly: Bool
        let user: User
        let password: String
    }

    @MainActor
    private final class FollowupRouteSpy: BrandRequestRouting {
        private(set) var detailCalls = 0
        private(set) var brandIDs: [BrandID] = []
        func pushBrandRequest(initialBrandName: String) {}
        func pushBrandDetail(brand: Brand) {
            detailCalls += 1
            brandIDs.append(brand.id)
        }
    }

    @MainActor
    private final class CurrentPublicReadSpy: LoadPublicBrandUseCaseProtocol {
        private let wrapped: any LoadPublicBrandUseCaseProtocol
        private(set) var brandIDs: [BrandID] = []
        private(set) var publicBrandIDs: [BrandID] = []
        init(wrapped: any LoadPublicBrandUseCaseProtocol) { self.wrapped = wrapped }
        func execute(brandID: BrandID) async throws -> Brand {
            brandIDs.append(brandID)
            let brand = try await wrapped.execute(brandID: brandID)
            if brand.isVisibleToUsers { publicBrandIDs.append(brand.id) }
            return brand
        }
    }

    @Test func testReadAddedHistoryAndOpenCurrentPublicBrandWithRealLocalSDK() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let targetPath = environment["OUTPICK_BRAND_LOCAL_TARGET"],
              let loginPath = environment["OUTPICK_BRAND_LOCAL_LOGIN"],
              let outputPath = environment["OUTPICK_BRAND_LOCAL_OUTPUT"],
              let groupID = environment["OUTPICK_BRAND_LOCAL_GROUP"],
              let brandID = environment["OUTPICK_BRAND_LOCAL_BRAND"],
              let expectedRound = environment["OUTPICK_BRAND_LOCAL_ROUND"],
              let publicationHash = environment["OUTPICK_BRAND_LOCAL_PUBLICATION_SHA256"] else {
            throw BrandLocalIntegrationError.unavailableConfiguration
        }
        let target = try BrandLocalIntegrationTarget(data: Data(contentsOf: URL(fileURLWithPath: targetPath)))
        let login = try JSONDecoder().decode(Login.self, from: Data(contentsOf: URL(fileURLWithPath: loginPath)))
        guard target.roundID == expectedRound, login.projectID == "outpick-test", login.syntheticLocalOnly,
              publicationHash.count == 64, !groupID.isEmpty, !brandID.isEmpty else {
            throw BrandLocalIntegrationError.invalidTarget
        }
        let context = try AppCompositionRoot.makeBrandLocalIntegration(target: target)
        defer { try? context.auth.signOut() }
        var evidence: [String: Any] = ["roundID": target.roundID, "groupID": groupID,
            "expectedBrandID": brandID, "backendPublicationEvidenceSHA256": publicationHash,
            "mode": "actual-Firebase-iOS-SDK-local-after-publication", "generalUserTenant": NSNull(),
            "requestSubmitted": false, "publicationExecutedByIOS": false, "appCheckProviderDisabled": true,
            "credentialsIncluded": false, "simulatorUITested": false, "physicalDeviceTested": false]
        var steps: [String] = []
        func checkpoint(_ id: String) throws {
            steps.append(id)
            evidence["completedSteps"] = steps
            evidence["observedAt"] = ISO8601DateFormatter().string(from: Date())
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
        do {
            let user = try await context.auth.signIn(withEmail: login.user.email, password: login.password)
            guard user.user.uid == login.user.uid, context.auth.tenantID == nil else {
                throw BrandLocalIntegrationError.invalidTarget
            }
            try checkpoint("PUBLISHED01-local-general-auth")
            let list = ListMyBrandRequestsUseCase(repository: context.requests)
            func readAll(_ scope: BrandRequestListScope) async throws -> [BrandRequest] {
                var rows: [BrandRequest] = []
                var cursor: BrandRequestPage.Cursor?
                var consumed: [BrandRequestPage.Cursor] = []
                var pages: [[String: Any]] = []
                repeat {
                    let page = try await list.execute(scope: scope, limit: 50, cursor: cursor)
                    rows.append(contentsOf: page.requests)
                    pages.append(["rows": page.requests.count, "nextCursor": page.nextCursor.map {
                        ["createdAt": $0.createdAt, "requestID": $0.requestID] as Any
                    } ?? NSNull()])
                    cursor = page.nextCursor
                    if let cursor {
                        guard !consumed.contains(cursor) else { throw CloudFunctionsClientError.invalidResponse }
                        consumed.append(cursor)
                    }
                } while cursor != nil
                evidence[scope.rawValue + "Pages"] = pages
                return rows
            }
            let active = try await readAll(.active)
            let history = try await readAll(.history)
            #expect(!active.contains(where: { $0.groupID == groupID }))
            let row = try #require(history.first(where: { $0.groupID == groupID }))
            #expect(row.status == .added)
            #expect(row.resolvedBrandID?.value == brandID)
            #expect(row.rejectionReason == nil)
            evidence["requestID"] = row.id
            evidence["status"] = row.status.rawValue
            evidence["resolvedBrandID"] = row.resolvedBrandID.map { $0.value as Any } ?? NSNull()
            evidence["activeRows"] = active.count
            evidence["historyRows"] = history.count
            try checkpoint("PUBLISHED02-added-and-scope-cursors")
            let currentPublic = CurrentPublicReadSpy(wrapped: LoadPublicBrandUseCase(repository: context.brands))
            let model = MyBrandRequestsViewModel(scope: .history, listUseCase: list,
                loadBrandUseCase: currentPublic, pageLimit: 50)
            await model.loadInitial()
            while !model.requests.contains(where: { $0.groupID == groupID }), model.canLoadNextPage,
                  let last = model.requests.last {
                await model.loadNextPageIfNeeded(current: last)
                if case .failed = model.phase { break }
            }
            #expect(model.phase == .ready)
            let displayed = try #require(model.requests.first(where: { $0.groupID == groupID }))
            #expect(displayed.status == .added)
            #expect(displayed.resolvedBrandID?.value == brandID)
            let route = FollowupRouteSpy()
            #expect(currentPublic.brandIDs.isEmpty)
            #expect(route.detailCalls == 0)
            await model.openCompletedBrand(displayed, using: route)
            #expect(currentPublic.brandIDs.map(\.value) == [brandID])
            #expect(currentPublic.publicBrandIDs.map(\.value) == [brandID])
            #expect(route.brandIDs.map(\.value) == [brandID])
            #expect(route.detailCalls == 1)
            #expect(model.navigationError == nil)
            evidence["viewModelPhase"] = "ready"
            evidence["displayTitle"] = displayed.status.displayTitle
            evidence["currentPublicReadIDs"] = currentPublic.brandIDs.map(\.value)
            evidence["verifiedPublicIDs"] = currentPublic.publicBrandIDs.map(\.value)
            evidence["coordinatorSpyBrandIDs"] = route.brandIDs.map(\.value)
            evidence["coordinatorSpyDetailCalls"] = route.detailCalls
            try checkpoint("PUBLISHED03-current-public-read-before-explicit-navigation")
            #expect(FirebaseApp.app() == nil)
            evidence["defaultFirebaseAppCreated"] = FirebaseApp.app() != nil
            try checkpoint("PUBLISHED04-isolation-and-finished")
        } catch {
            evidence["failureDomain"] = (error as NSError).domain
            evidence["failureCode"] = (error as NSError).code
            try checkpoint("PUBLISHED-failed")
            Issue.record(" 게시 후 SDK 조회를 완료하지 못했습니다. 비밀 없는 단계 기록을 확인하세요.")
        }
    }

    @Test func testReadReviewingHistoryAfterWebProcessingWithRealLocalSDK() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let targetPath = environment["OUTPICK_BRAND_LOCAL_TARGET"],
              let loginPath = environment["OUTPICK_BRAND_LOCAL_LOGIN"],
              let outputPath = environment["OUTPICK_BRAND_LOCAL_OUTPUT"],
              let groupID = environment["OUTPICK_BRAND_LOCAL_GROUP"] else {
            throw BrandLocalIntegrationError.unavailableConfiguration
        }
        let target = try BrandLocalIntegrationTarget(data: Data(contentsOf: URL(fileURLWithPath: targetPath)))
        let login = try JSONDecoder().decode(Login.self, from: Data(contentsOf: URL(fileURLWithPath: loginPath)))
        guard login.projectID == "outpick-test", login.syntheticLocalOnly else {
            throw BrandLocalIntegrationError.invalidTarget
        }
        let context = try AppCompositionRoot.makeBrandLocalIntegration(target: target)
        defer { try? context.auth.signOut() }
        var evidence: [String: Any] = ["roundID": target.roundID, "groupID": groupID,
            "mode": "actual-Firebase-iOS-SDK-local-followup", "generalUserTenant": NSNull(),
            "requestSubmitted": false, "imagePublicationExecuted": false,
            "appCheckProviderDisabled": true,
            "expectationSource": "사용자 전달: 웹 publicationPending/workflowRevision9; 공개 기대 reviewing/null",
            "credentialsIncluded": false]
        var steps: [String] = []
        func checkpoint(_ id: String) throws {
            steps.append(id)
            evidence["completedSteps"] = steps
            evidence["observedAt"] = ISO8601DateFormatter().string(from: Date())
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
        do {
            let result = try await context.auth.signIn(withEmail: login.user.email, password: login.password)
            guard result.user.uid == login.user.uid, context.auth.tenantID == nil else {
                throw BrandLocalIntegrationError.invalidTarget
            }
            try checkpoint("FOLLOWUP01-local-general-auth")
            let list = ListMyBrandRequestsUseCase(repository: context.requests)
            let active = try await list.execute(scope: .active, limit: 50, cursor: nil)
            let row = try #require(active.requests.first(where: { $0.groupID == groupID }))
            #expect(row.status == .reviewing)
            #expect(row.resolvedBrandID == nil)
            #expect(row.rejectionReason == nil)
            evidence["requestID"] = row.id
            evidence["status"] = row.status.rawValue
            evidence["resolvedBrandID"] = row.resolvedBrandID.map { $0.value as Any } ?? NSNull()
            evidence["activeRows"] = active.requests.count
            evidence["activeNextCursorIsNull"] = active.nextCursor == nil
            try checkpoint("FOLLOWUP02-strict-public-history-reviewing-null")
            let model = MyBrandRequestsViewModel(listUseCase: list,
                loadBrandUseCase: LoadPublicBrandUseCase(repository: context.brands))
            await model.loadInitial()
            #expect(model.phase == .ready)
            let displayed = try #require(model.requests.first(where: { $0.groupID == groupID }))
            #expect(displayed.status == .reviewing)
            #expect(displayed.status.displayTitle == "처리 중")
            #expect(displayed.resolvedBrandID == nil)
            let route = FollowupRouteSpy()
            await model.openCompletedBrand(displayed, using: route)
            #expect(route.detailCalls == 0)
            evidence["viewModelPhase"] = "ready"
            evidence["displayTitle"] = displayed.status.displayTitle
            evidence["coordinatorDetailCalls"] = route.detailCalls
            try checkpoint("FOLLOWUP03-viewmodel-and-route-spy")
            let history = try await list.execute(scope: .history, limit: 50, cursor: nil)
            #expect(!history.requests.contains(where: { $0.groupID == groupID }))
            evidence["historyRows"] = history.requests.count
            evidence["historyNextCursorIsNull"] = history.nextCursor == nil
            #expect(FirebaseApp.app() == nil)
            evidence["defaultFirebaseAppCreated"] = FirebaseApp.app() != nil
            try checkpoint("FOLLOWUP04-history-scope-and-isolation")
        } catch {
            evidence["failureDomain"] = (error as NSError).domain
            evidence["failureCode"] = (error as NSError).code
            try checkpoint("FOLLOWUP-failed")
            Issue.record("후속 SDK 조회를 완료하지 못했습니다. 비밀 없는 단계 기록을 확인하세요.")
        }
    }

    @Test func testSubmitDuplicateAndReadInitialHistoryWithRealLocalSDK() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let targetPath = environment["OUTPICK_BRAND_LOCAL_TARGET"],
              let loginPath = environment["OUTPICK_BRAND_LOCAL_LOGIN"],
              let outputPath = environment["OUTPICK_BRAND_LOCAL_OUTPUT"] else {
            throw BrandLocalIntegrationError.unavailableConfiguration
        }
        guard BrandLocalIntegrationMode.isEnabled, FirebaseApp.app() == nil else {
            throw BrandLocalIntegrationError.isolatedModeRequired
        }
        let target = try BrandLocalIntegrationTarget(data: Data(contentsOf: URL(fileURLWithPath: targetPath)))
        let login = try JSONDecoder().decode(Login.self, from: Data(contentsOf: URL(fileURLWithPath: loginPath)))
        guard login.projectID == "outpick-test", login.syntheticLocalOnly else {
            throw BrandLocalIntegrationError.invalidTarget
        }
        let context = try AppCompositionRoot.makeBrandLocalIntegration(target: target)
        var evidence: [String: Any] = ["roundID": target.roundID, "mode": "actual-Firebase-iOS-SDK-local",
            "generalUserTenant": NSNull(), "defaultFirebaseAppCreated": false,
            "imagePublicationExecuted": false, "remoteIndexReadinessClaim": false]
        var steps: [String] = []
        func checkpoint(_ id: String) throws {
            steps.append(id)
            evidence["completedSteps"] = steps
            evidence["observedAt"] = ISO8601DateFormatter().string(from: Date())
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
        defer { try? context.auth.signOut() }
        do {
            try checkpoint("SDK00-isolated-clients-created")
            let result = try await context.auth.signIn(withEmail: login.user.email, password: login.password)
            guard result.user.uid == login.user.uid, context.auth.tenantID == nil else {
                throw BrandLocalIntegrationError.invalidTarget
            }
            try checkpoint("SDK01-local-general-auth")
            let name = "iOS L153 " + target.roundID.prefix(8)
            let submit = SubmitBrandRequestUseCase(repository: context.requests)
            let receipt = try await submit.execute(brandName: name,
                websiteURL: "https://ios-local.example.invalid/brand", englishBrandName: nil)
            evidence["requestID"] = receipt.requestID
            evidence["groupID"] = receipt.groupID
            evidence["status"] = receipt.status.rawValue
            evidence["firstResponseIsDuplicate"] = receipt.isDuplicate
            evidence["remainingToday"] = receipt.remainingToday
            evidence["resolvedBrandID"] = receipt.resolvedBrandID.map { $0.value as Any } ?? NSNull()
            try checkpoint("SDK02-submit-strict-receipt")
            let duplicate = try await submit.execute(brandName: name,
                websiteURL: "https://ios-local.example.invalid/brand", englishBrandName: "Local")
            guard duplicate.isDuplicate, duplicate.requestID == receipt.requestID,
                  duplicate.groupID == receipt.groupID, duplicate.remainingToday == receipt.remainingToday else {
                throw BrandLocalIntegrationError.invalidTarget
            }
            try checkpoint("SDK03-duplicate-current-receipt")
            let history = ListMyBrandRequestsUseCase(repository: context.requests)
            let active = try await history.execute(scope: .active, limit: 20, cursor: nil)
            guard active.requests.contains(where: { $0.id == receipt.requestID }),
                  active.requests.allSatisfy({ [.submitted, .reviewing].contains($0.status) }) else {
                throw BrandLocalIntegrationError.invalidTarget
            }
            _ = try await history.execute(scope: .history, limit: 20, cursor: nil)
            evidence["initialRequestHistoryMatched"] = true
            try checkpoint("SDK04-actual-history")
            var queryCounts: [String: Int] = [:]
            for sort in [nil, BrandSort.latest, .popular, .likes, .views] as [BrandSort?] {
                let key = sort.map { String(describing: $0) } ?? "documentID"
                let all = try await context.brands.fetchBrands(sort: sort, limit: 20, after: nil)
                let featured = try await context.brands.fetchFeaturedBrands(sort: sort, limit: 20, after: nil)
                guard all.items.allSatisfy(\.isVisibleToUsers), featured.items.allSatisfy(\.isVisibleToUsers) else {
                    throw BrandLocalIntegrationError.invalidTarget
                }
                queryCounts["general-" + key] = all.items.count
                queryCounts["featured-" + key] = featured.items.count
            }
            let interest = try await context.brands.fetchInterestedStyleBrands(moodIDs: ["fixture-style"], limit: 10, after: nil)
            queryCounts["interested"] = interest.items.count
            evidence["actualQueryCounts"] = queryCounts
            evidence["positivePublicFixtureVerified"] = false
            try checkpoint("SDK05-actual-query-transport-and-rules")
            var missingBlocked = false
            do {
                _ = try await LoadPublicBrandUseCase(repository: context.brands).execute(brandID: .init(value: "ios-local-missing"))
            } catch {
                if case LookbookContentUnavailableError.brandUnavailable = error { missingBlocked = true }
                else {
                    let failure = error as NSError
                    guard failure.domain == FirestoreErrorDomain, failure.code == FirestoreErrorCode.permissionDenied.rawValue else {
                        throw error
                    }
                    missingBlocked = true
                }
            }
            guard missingBlocked else { throw BrandLocalIntegrationError.invalidTarget }
            evidence["missingBrandBlocked"] = true
            try checkpoint("SDK06-missing-brand-blocked")
            try context.auth.signOut()
            do {
                _ = try await history.execute(scope: .active, limit: 20, cursor: nil)
                throw BrandLocalIntegrationError.invalidTarget
            } catch {
                guard error as? BrandRequestFailure == .unauthenticated else { throw error }
            }
            try checkpoint("SDK07-actual-unauthenticated-error")
            evidence["webProcessingMayStart"] = true
            try checkpoint("SDK08-ready-for-web-processing")
            guard FirebaseApp.app() == nil else { throw BrandLocalIntegrationError.isolatedModeRequired }
        } catch {
            // SDK 오류의 userInfo·인증 입력을 진단 출력에 싣지 않는다.
            evidence["failureDomain"] = (error as NSError).domain
            evidence["failureCode"] = (error as NSError).code
            try checkpoint("SDK-failed")
            Issue.record("로컬 SDK 검사를 완료하지 못했습니다. 비밀 없는 단계 기록을 확인하세요.")
        }
    }
}
#endif
#endif
