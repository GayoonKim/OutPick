import Foundation
import FirebaseFirestore
import FirebaseFunctions
import SwiftUI
import Testing
import UIKit
@testable import OutPick

@MainActor
struct BrandOperationsTests {
    @Test func officialURLAndOptionalEnglishNameAreValidatedBeforeSubmission() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [receiptDictionary()]
        let repository = CloudFunctionsBrandRequestRepository(transport: transport)
        let useCase = SubmitBrandRequestUseCase(repository: repository)
        let model = BrandRequestViewModel(initialBrandName: "모노", submitUseCase: useCase,
                                          loadBrandUseCase: LoadPublicBrandUseCase(repository: BrandOperationsRepositoryFake()))
        #expect(!model.canSubmit)
        for url in ["", "ftp://mono.example", "https://actor:secret@mono.example", "https://"] {
            model.websiteURL = url
            #expect(await model.submit() == nil)
        }
        #expect(transport.calls.isEmpty)
        model.websiteURL = " https://mono.example/a?b=1 "
        let receipt = await model.submit()
        #expect(receipt?.status == .submitted)
        #expect(transport.calls.count == 1)
        #expect(transport.calls[0].data["websiteURL"] as? String == "https://mono.example/a?b=1")
        #expect(transport.calls[0].data["englishBrandName"] == nil)
        #expect(await model.submit() == nil)
    }

    @Test func inputBoundariesAndSchemeDefaultFollowPublicContract() {
        #expect(BrandRequestInput.isValid(brandName: "모노", websiteURL: "mono.example", englishBrandName: nil))
        #expect(!BrandRequestInput.isValid(brandName: " ", websiteURL: "https://mono.example", englishBrandName: nil))
        #expect(!BrandRequestInput.isValid(brandName: String(repeating: "가", count: 81), websiteURL: "mono.example", englishBrandName: nil))
        #expect(!BrandRequestInput.isValid(brandName: "모노", websiteURL: String(repeating: "a", count: 2049), englishBrandName: nil))
        #expect(!BrandRequestInput.isValid(brandName: "모노", websiteURL: "mono.example", englishBrandName: String(repeating: "a", count: 81)))
    }

    @Test func invalidReceiptLeavesHistoryIndependentAndRetriesOnlyOnUserSubmission() async throws {
        let transport = CloudFunctionsTransportSpy()
        var incomplete = receiptDictionary()
        incomplete.removeValue(forKey: "resolvedBrandID")
        var duplicate = receiptDictionary(status: "reviewing")
        duplicate["isDuplicate"] = true
        transport.responses = [incomplete, [
            "requests": [wireRequest("request")],
            "scope": "active", "nextCursor": NSNull()
        ], duplicate]
        let repository = CloudFunctionsBrandRequestRepository(transport: transport)
        let load = LoadPublicBrandUseCase(repository: BrandOperationsRepositoryFake())
        let form = BrandRequestViewModel(initialBrandName: "모노",
            submitUseCase: SubmitBrandRequestUseCase(repository: repository), loadBrandUseCase: load)
        form.websiteURL = " https://mono.example/official "
        form.englishBrandName = " Mono "

        #expect(await form.submit() == nil)
        #expect(form.receipt == nil && transport.calls.count == 1)
        #expect(form.submissionErrorMessage == "접수 결과를 확인하지 못했어요. 요청 내역을 확인해 주세요.")
        #expect(form.websiteURL == " https://mono.example/official " && form.englishBrandName == " Mono ")
        let history = MyBrandRequestsViewModel(
            listUseCase: ListMyBrandRequestsUseCase(repository: repository), loadBrandUseCase: load)
        await history.loadInitial()
        #expect(history.requests.map(\.id) == ["request"] && history.requests[0].status == .submitted)
        #expect(form.receipt == nil && transport.calls.map(\.name) == ["submitBrandRequest", "listMyBrandRequests"])
        form.dismissSubmissionError()
        #expect(transport.calls.count == 2)
        let retry = try #require(await form.submit())
        #expect(retry.requestID == "request" && retry.isDuplicate && retry.status == .reviewing)
        #expect(retry.remainingToday == 4 && retry.resolvedBrandID == nil)
        #expect(transport.calls.map(\.name) == ["submitBrandRequest", "listMyBrandRequests", "submitBrandRequest"])
        for call in [transport.calls[0], transport.calls[2]] {
            #expect(Set(call.data.keys) == ["brandName", "websiteURL", "englishBrandName"])
            #expect(call.data["brandName"] as? String == "모노")
            #expect(call.data["websiteURL"] as? String == "https://mono.example/official")
            #expect(call.data["englishBrandName"] as? String == "Mono")
        }
    }

    @Test func transportFailuresPreserveDraftAndDoNotRetryAutomatically() async {
        let failures: [(Error, String)] = [
            (functionsFailure(code: 8, reason: "DAILY_LIMIT_REACHED"), "오늘 요청 가능 횟수를 모두 사용했어요."),
            (functionsFailure(code: 7, reason: "REQUEST_BLOCKED"), "브랜드 요청이 제한된 계정이에요."),
            (URLError(.timedOut), "접수 결과를 확인하지 못했어요. 요청 내역을 확인해 주세요.")
        ]
        for (error, message) in failures {
            let transport = CloudFunctionsTransportSpy()
            transport.error = error
            let repository = CloudFunctionsBrandRequestRepository(transport: transport)
            let form = BrandRequestViewModel(initialBrandName: "모노",
                submitUseCase: SubmitBrandRequestUseCase(repository: repository),
                loadBrandUseCase: LoadPublicBrandUseCase(repository: BrandOperationsRepositoryFake()))
            form.websiteURL = "mono.example"
            #expect(await form.submit() == nil)
            #expect(form.submissionErrorMessage == message && form.receipt == nil)
            form.dismissSubmissionError()
            #expect(form.canSubmit && form.websiteURL == "mono.example" && transport.calls.count == 1)
        }
    }

    @Test func repositoryHistoryMapsFourStatesAndRoutesOnlyCurrentPublicCompletion() async throws {
        func row(_ id: String, _ status: String, _ brandID: String? = nil) -> [String: Any] {
            wireRequest(id, status: status, brandID: brandID)
        }
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [[
            "scope": "active", "nextCursor": NSNull(),
            "requests": [row("submitted", "submitted"), row("reviewing", "reviewing")]
        ], [
            "scope": "history", "nextCursor": NSNull(),
            "requests": [row("hold", "rejected"), row("complete", "added", "public-brand"), row("unavailable", "added")]
        ]]
        let brands = BrandOperationsRepositoryFake()
        let model = MyBrandRequestsViewModel(
            listUseCase: ListMyBrandRequestsUseCase(repository: CloudFunctionsBrandRequestRepository(transport: transport)),
            loadBrandUseCase: LoadPublicBrandUseCase(repository: brands))
        await model.loadInitial()
        #expect(model.requests.map(\.status) == [.submitted, .reviewing])
        await model.selectScope(.history)
        #expect(model.requests.map(\.status) == [.rejected, .added, .added])
        #expect(model.requests.first?.rejectionReason == "공식 룩북 확인 필요")
        let completed = try #require(model.requests.first { $0.id == "complete" })
        let unavailable = try #require(model.requests.first { $0.id == "unavailable" })
        let router = BrandOperationsCoordinatorSpy()
        await model.openCompletedBrand(unavailable, using: router)
        #expect(brands.readIDs.isEmpty && router.brands.isEmpty)
        await model.openCompletedBrand(completed, using: router)
        #expect(router.brands.map(\.id.value) == ["public-brand"])
        brands.brand.publicationStatus = "pending"
        await model.openCompletedBrand(completed, using: router)
        #expect(router.brands.count == 1 && model.navigationError != nil)
        #expect(model.requests.map(\.id) == ["hold", "complete", "unavailable"])
        #expect(transport.calls.map { $0.data["scope"] as? String } == ["active", "history"])
    }

    @Test func repositoryPaginationRetriesTheSameCursorWithoutLosingLoadedRows() async throws {
        func row(_ id: String) -> [String: Any] {
            wireRequest(id)
        }
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [[
            "scope": "active", "requests": [row("a")],
            "nextCursor": ["createdAt": "2026-10-15T00:00:00.000Z", "requestID": "a"]
        ], ["scope": "active", "requests": [row("a"), row("b")], "nextCursor": NSNull()]]
        let model = MyBrandRequestsViewModel(
            listUseCase: ListMyBrandRequestsUseCase(repository: CloudFunctionsBrandRequestRepository(transport: transport)),
            loadBrandUseCase: LoadPublicBrandUseCase(repository: BrandOperationsRepositoryFake()), pageLimit: 20)
        await model.loadInitial()
        #expect(model.requests.map(\.id) == ["a"] && model.canLoadNextPage)
        transport.error = URLError(.notConnectedToInternet)
        await model.loadNextPageIfNeeded(current: try #require(model.requests.first))
        #expect(model.requests.map(\.id) == ["a"] && model.canLoadNextPage)
        if case .failed = model.phase {} else { Issue.record("페이지 오류가 표시되어야 한다") }
        transport.error = nil
        await model.loadNextPageIfNeeded(current: try #require(model.requests.first))
        #expect(model.requests.map(\.id) == ["a", "b"] && !model.canLoadNextPage && model.phase == .ready)
        #expect(transport.calls.count == 3 && transport.calls[0].data["cursorRequestID"] == nil)
        for call in transport.calls.dropFirst() {
            #expect(call.name == "listMyBrandRequests")
            #expect(call.data["scope"] as? String == "active" && call.data["limit"] as? Int == 20)
            #expect(call.data["cursorCreatedAt"] as? String == "2026-10-15T00:00:00.000Z")
            #expect(call.data["cursorRequestID"] as? String == "a")
        }
    }

    @Test func receiptRejectsMissingUnknownAndMalformedValues() throws {
        let valid = receiptDictionary(status: "added", brandID: "public-brand")
        #expect(try BrandRequestCloudFunctionsMapper.submissionReceipt(valid).destinationBrandID?.value == "public-brand")
        for field in ["requestID", "groupID", "status", "isDuplicate", "remainingToday", "resolvedBrandID"] {
            var invalid = valid
            invalid.removeValue(forKey: field)
            #expect(throws: (any Error).self) { try BrandRequestCloudFunctionsMapper.submissionReceipt(invalid) }
        }
        for (field, value) in [("status", "pending" as Any), ("resolvedBrandID", "" as Any),
                               ("groupID", 1 as Any), ("groupID", "" as Any),
                               ("resolvedBrandID", "  " as Any),
            ("groupID", NSNull() as Any), ("requestID", "" as Any),
            ("remainingToday", -1 as Any), ("remainingToday", 0.5 as Any),
                               ("isDuplicate", 1 as Any)] {
            var invalid = valid
            invalid[field] = value
            #expect(throws: (any Error).self) { try BrandRequestCloudFunctionsMapper.submissionReceipt(invalid) }
        }
    }

    @Test func lostOrInvalidResponseKeepsInputsAndOnlyManualRetrySendsAgain() async {
        let submit = BrandOperationsSubmitFake()
        submit.results = [.failure(CloudFunctionsClientError.invalidResponse), .success(receipt(status: .reviewing, duplicate: true))]
        let model = BrandRequestViewModel(initialBrandName: "모노", submitUseCase: submit,
                                          loadBrandUseCase: LoadPublicBrandUseCase(repository: BrandOperationsRepositoryFake()))
        model.websiteURL = "mono.example"
        model.englishBrandName = "Mono"
        #expect(await model.submit() == nil)
        #expect(model.brandName == "모노" && model.websiteURL == "mono.example" && model.englishBrandName == "Mono")
        #expect(submit.inputs.count == 1)
        let result = await model.submit()
        #expect(result?.isDuplicate == true && result?.status == .reviewing)
        #expect(submit.inputs.count == 2 && submit.inputs[0] == submit.inputs[1])
    }

    @Test func submissionErrorsHideTechnicalDetailsAndDismissWithoutLosingDraft() async {
        let errors: [Error] = [
            CloudFunctionsClientError.missingField("resolvedBrandID"),
            URLError(.notConnectedToInternet),
            NSError(domain: "InternalTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "비공개 기술 오류"])
        ]
        for error in errors {
            let submit = BrandOperationsSubmitFake()
            submit.results = [.failure(error), .success(receipt(status: .submitted))]
            let model = BrandRequestViewModel(initialBrandName: "모노", submitUseCase: submit,
                loadBrandUseCase: LoadPublicBrandUseCase(repository: BrandOperationsRepositoryFake()))
            model.websiteURL = "mono.example"
            model.englishBrandName = "Mono"
            #expect(await model.submit() == nil)
            #expect(model.submissionErrorMessage == "접수 결과를 확인하지 못했어요. 요청 내역을 확인해 주세요.")
            #expect(model.receipt == nil && submit.inputs.count == 1)

            model.dismissSubmissionError()
            #expect(model.phase == .idle && model.submissionErrorMessage == nil && model.canSubmit)
            #expect(model.brandName == "모노" && model.websiteURL == "mono.example" && model.englishBrandName == "Mono")
            #expect(submit.inputs.count == 1)
            #expect(await model.submit() != nil)
            #expect(submit.inputs.count == 2 && submit.inputs[0] == submit.inputs[1])
            model.dismissSubmissionError()
            #expect(model.receipt != nil)
        }
    }

    @Test func submissionLimitAndRestrictionKeepActionableMessages() async {
        for (error, message) in [(BrandRequestFailure.dailyLimit, "오늘 요청 가능 횟수를 모두 사용했어요."),
                                  (.requestBlocked, "브랜드 요청이 제한된 계정이에요.")] {
            let submit = BrandOperationsSubmitFake()
            submit.results = [.failure(error)]
            let model = BrandRequestViewModel(initialBrandName: "모노", submitUseCase: submit,
                loadBrandUseCase: LoadPublicBrandUseCase(repository: BrandOperationsRepositoryFake()))
            model.websiteURL = "mono.example"
            _ = await model.submit()
            #expect(model.submissionErrorMessage == message)
        }
    }

    @Test func fourStatusesHoldReasonAndNullableCompletionArePreserved() throws {
        #expect(BrandRequestStatus.allCases.map(\.displayTitle) == ["요청 접수", "처리 중", "등록 완료", "보류"])
        for status in BrandRequestStatus.allCases {
            let mapped = try BrandRequestCloudFunctionsMapper.request(wireRequest("request", status: status.rawValue))
            #expect(mapped.status == status && mapped.resolvedBrandID == nil)
            #expect(mapped.rejectionReason == (status == .rejected ? "공식 룩북 확인 필요" : nil))
        }
        #expect(receipt(status: .added).destinationBrandID == nil)
    }

    @Test func completedNavigationRechecksPublicBrandAndNullNeverRoutes() async {
        let repository = BrandOperationsRepositoryFake()
        let load = LoadPublicBrandUseCase(repository: repository)
        let list = BrandOperationsHistoryFake()
        let model = MyBrandRequestsViewModel(listUseCase: list, loadBrandUseCase: load)
        let router = BrandOperationsCoordinatorSpy()
        await model.openCompletedBrand(request("null", status: .added), using: router)
        #expect(repository.readIDs.isEmpty && router.brands.isEmpty)
        await model.openCompletedBrand(request("public", status: .added, brandID: "public-brand"), using: router)
        #expect(router.brands.map(\.id.value) == ["public-brand"])
        repository.brand.publicationStatus = "pending"
        await model.openCompletedBrand(request("pending", status: .added, brandID: "public-brand"), using: router)
        #expect(router.brands.count == 1 && model.navigationError != nil)
    }

    @Test func submissionCompletionRoutesOnlyWhenPublicIDIsPresent() async {
        let submit = BrandOperationsSubmitFake()
        submit.results = [.success(receipt(status: .added, brandID: "public-brand"))]
        let repository = BrandOperationsRepositoryFake()
        let model = BrandRequestViewModel(initialBrandName: "모노", submitUseCase: submit,
                                          loadBrandUseCase: LoadPublicBrandUseCase(repository: repository))
        model.websiteURL = "mono.example"
        _ = await model.submit()
        let router = BrandOperationsCoordinatorSpy()
        await model.openCompletedBrand(using: router)
        #expect(router.brands.map(\.id.value) == ["public-brand"])
    }

    @Test func scopeSwitchCancelsOldTaskAndDiscardsLatePage() async {
        let list = BrandOperationsHistoryFake()
        list.suspendActive = true
        let model = MyBrandRequestsViewModel(listUseCase: list,
            loadBrandUseCase: LoadPublicBrandUseCase(repository: BrandOperationsRepositoryFake()))
        let old = Task { await model.reload() }
        await list.waitForActive()
        await model.selectScope(.history)
        #expect(model.scope == .history && model.requests.map(\.id) == ["history"])
        list.finishActive()
        await old.value
        #expect(list.activeWasCancelled)
        #expect(model.requests.map(\.id) == ["history"] && model.phase == .ready)
    }

    @Test func paginationDeduplicatesAndKeepsAlreadyLoadedRowsOnFailure() async {
        let list = BrandOperationsHistoryFake()
        list.pages = [
            .success(BrandRequestPage(requests: [request("a")], nextCursor: .init(createdAt: "date", requestID: "a"), scope: .active)),
            .success(BrandRequestPage(requests: [request("a"), request("b")], nextCursor: .init(createdAt: "date", requestID: "b"), scope: .active)),
            .failure(URLError(.notConnectedToInternet))
        ]
        let model = MyBrandRequestsViewModel(listUseCase: list,
            loadBrandUseCase: LoadPublicBrandUseCase(repository: BrandOperationsRepositoryFake()))
        await model.loadInitial()
        await model.loadNextPageIfNeeded(current: model.requests[0])
        #expect(model.requests.map(\.id) == ["a", "b"])
        await model.loadNextPageIfNeeded(current: model.requests[1])
        #expect(model.requests.map(\.id) == ["a", "b"])
        #expect(list.calls.count == 3)
    }

    @Test func publicationDTORejectsMissingUnknownPendingAndDeletedStates() throws {
        for status in [nil, "pending", "unexpected", "public"] as [String?] {
            var value: [String: Any] = ["name": "브랜드"]
            if let status { value["publicationStatus"] = status }
            let dto = try JSONDecoder().decode(BrandDTO.self, from: JSONSerialization.data(withJSONObject: value))
            let brand = try dto.toDomain(documentID: "brand")
            #expect(brand.isVisibleToUsers == (status == "public"))
        }
        var deleted = publicBrand()
        deleted.deletionStatus = .deletionRequested
        #expect(!deleted.isVisibleToUsers)
    }

    @Test func publicBrandUseCasePropagatesReadErrorsWithoutEmptySuccess() async {
        let repository = BrandOperationsRepositoryFake()
        repository.error = URLError(.notConnectedToInternet)
        await #expect(throws: (any Error).self) {
            try await LoadPublicBrandUseCase(repository: repository).execute(brandID: .init(value: "public-brand"))
        }
    }

    @Test func likedBrandsExcludePendingAndPropagateReadFailure() async throws {
        let repository = BrandOperationsRepositoryFake()
        let states = BrandOperationsUserStateFake()
        let load = LoadLikedBrandsUseCase(brandUserStateRepository: states, brandRepository: repository)
        repository.brand.publicationStatus = "pending"
        #expect(try await load.execute(userID: .init(value: "user"), limit: 20, after: nil).items.isEmpty)
        repository.brand.publicationStatus = "public"
        #expect(try await load.execute(userID: .init(value: "user"), limit: 20, after: nil).items.count == 1)
        repository.error = URLError(.notConnectedToInternet)
        await #expect(throws: (any Error).self) {
            try await load.execute(userID: .init(value: "user"), limit: 20, after: nil)
        }
    }

    @Test func newAndExistingBrandSharesHaveNoDisplayImageAndKeepStoredSnapshot() async throws {
        let repository = BrandOperationsRepositoryFake()
        let existing = LookbookSharedContent(schemaVersion: 1, contentType: .brand, brandID: "public-brand",
            titleSnapshot: "모노", thumbnailPathSnapshot: "brands/old-logo")
        #expect(existing.thumbnailPathSnapshot == "brands/old-logo" && existing.displayThumbnailPath == nil)
        #expect(existing.toDict()["thumbnailPathSnapshot"] as? String == "brands/old-logo")
        let useCase = MakeLookbookSharedContentUseCase(brandRepository: repository,
                                                       seasonRepository: BrandOperationsSeasonFake())
        let new = try await useCase.execute(target: .brand(publicBrand()))
        #expect(new.thumbnailPathSnapshot == nil && new.displayThumbnailPath == nil)
        let season = LookbookSharedContent(schemaVersion: 1, contentType: .season, brandID: "public-brand",
            seasonID: "season", titleSnapshot: "시즌", thumbnailPathSnapshot: "seasons/cover")
        #expect(season.displayThumbnailPath == "seasons/cover")
    }

    @Test func brandCardsAndHeaderMakeZeroImageRequestsWhileSeasonAndLookbookLoad() async throws {
        let cache = BrandOperationsImageSpy()
        let brand = publicBrand()
        let state = BrandUserState(brandID: brand.id, userID: .init(value: "user"), isLiked: true, updatedAt: Date())
        let cards = VStack {
            BrandRowView(brand: brand, brandImageCache: cache)
            InterestedStyleBrandCardView(brand: brand, brandImageCache: cache)
            LikedBrandCardView(item: .init(brand: brand, userState: state), brandImageCache: cache)
            BrandDetailHeaderView(brand: brand, likeCount: 1, isLiked: false, isMutatingLike: false,
                                 brandImageCache: cache, maxBytes: 1000, onLikeTap: {}, onShareTap: {})
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 900))
        let host = UIHostingController(rootView: AnyView(cards))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        defer { window.isHidden = true }
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(await cache.paths.isEmpty)
        host.rootView = AnyView(VStack {
            cards
            SeasonCoverThumbView(thumbPath: "seasons/cover", fallbackPath: nil, remoteURL: nil,
                                 sourcePageURL: nil, brandImageCache: cache, maxBytes: 1000)
            LookbookAssetImageView(primaryPath: "posts/image", secondaryPath: nil, remoteURL: nil,
                                   sourcePageURL: nil, brandImageCache: cache, maxBytes: 1000)
        })
        host.view.layoutIfNeeded()
        for _ in 0..<100 {
            if await cache.paths.count == 2 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(await Set(cache.paths) == Set(["seasons/cover", "posts/image"]))
    }
}

@MainActor
struct BrandOperationsL151Tests {
    private func fixtures(_ key: String) throws -> [[String: Any]] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("contracts/brand-operations/public-fixtures-v1.json"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(object[key] as? [[String: Any]])
    }

    @Test func publicResponseFixtures42PassThroughRepositoryAndRejectDamage() async throws {
        let cases = try fixtures("wireResponseCases")
        #expect(cases.count == 42)
        for row in cases {
            let id = try #require(row["id"] as? String)
            let valid = try #require(row["valid"] as? Bool)
            let response = try #require(row["response"] as? [String: Any])
            let transport = CloudFunctionsTransportSpy()
            transport.responses = [response]
            let repository = CloudFunctionsBrandRequestRepository(transport: transport)
            do {
                if row["endpoint"] as? String == "submitBrandRequest" {
                    _ = try await repository.submitBrandRequest(brandName: "모노", websiteURL: "https://example.invalid/", englishBrandName: nil)
                } else {
                    let scope: BrandRequestListScope = response["scope"] as? String == "history" ? .history : .active
                    _ = try await repository.listMyBrandRequests(scope: scope, limit: 20, cursor: nil)
                }
                #expect(valid, "손상 응답을 허용함: \(id)")
            } catch {
                #expect(!valid, "정상 응답을 거절함: \(id), \(error)")
            }
            #expect(transport.calls.count == 1)
        }
    }

    @Test func requiredTypesDatesReasonsAndScopeAreStrict() throws {
        let valid = wireRequest("request", status: "added")
        for key in valid.keys {
            var wrong = valid
            wrong[key] = 1
            #expect(throws: (any Error).self) { try BrandRequestCloudFunctionsMapper.request(wrong) }
            if !["englishBrandName", "resolvedBrandID", "rejectionReason"].contains(key) {
                wrong[key] = NSNull()
                #expect(throws: (any Error).self) { try BrandRequestCloudFunctionsMapper.request(wrong) }
            }
        }
        for value in ["2026-10-15", "2026-10-15T00:00:00Z", "2026-10-15T00:00:00.00Z",
                      "2026-10-15T09:00:00.000+09:00", "2026-02-30T00:00:00.000Z", "2026-10-15T24:00:00.000Z"] {
            var wrong = valid
            wrong["updatedAt"] = value
            #expect(throws: (any Error).self) { try BrandRequestCloudFunctionsMapper.request(wrong) }
        }
        for url in ["mono.example", "https://mono.example", "https://MONO.example/", "https://mono.example:443/", "ftp://mono.example/"] {
            var wrong = valid
            wrong["websiteURL"] = url
            #expect(throws: (any Error).self) { try BrandRequestCloudFunctionsMapper.request(wrong) }
        }
        var longName = valid
        longName["brandName"] = String(repeating: "🧥", count: 50)
        #expect(try BrandRequestCloudFunctionsMapper.request(longName).brandName.utf16.count == 100)
        #expect(!BrandRequestInput.isValid(brandName: String(repeating: "🧥", count: 41), websiteURL: "mono.example", englishBrandName: nil))
        for reason in ["공식 룩북 확인 필요", "이용 허락 확인 필요", "브랜드 정보 확인 필요", "기타"] {
            var hold = wireRequest("hold", status: "rejected")
            hold["rejectionReason"] = reason
            #expect(try BrandRequestCloudFunctionsMapper.request(hold).rejectionReason == reason)
        }
        let page: [String: Any] = ["scope": "history", "requests": [valid], "nextCursor": NSNull()]
        #expect(throws: (any Error).self) { try BrandRequestCloudFunctionsMapper.historyPage(page, scope: .active) }
        for requests: Any in [NSNull(), "rows", [1], Array(repeating: valid, count: 51)] {
            var wrong = page
            wrong["requests"] = requests
            #expect(throws: (any Error).self) { try BrandRequestCloudFunctionsMapper.historyPage(wrong, scope: .history) }
        }
        for value: Any in [true, "5", -1, 6, 1.5, Double.infinity, Double.nan] {
            var wrong = receiptDictionary()
            wrong["remainingToday"] = value
            #expect(throws: (any Error).self) { try BrandRequestCloudFunctionsMapper.submissionReceipt(wrong) }
        }
    }

    @Test func publicErrorFixtures9UseCodeAndOptionalReasonWithoutLosingDraft() async throws {
        let expected: [String: BrandRequestFailure] = [
            "error-invalid-input": .invalidInput, "error-invalid-cursor": .invalidCursor,
            "error-daily-limit": .dailyLimit, "error-request-blocked": .requestBlocked,
            "error-query-budget": .queryBudget, "error-invalid-stored-data": .invalidStoredData,
            "error-signed-out": .unauthenticated, "error-non-service-identity": .permissionDenied,
            "error-sdk-unavailable": .unavailable
        ]
        let codes = ["invalid-argument": 3, "resource-exhausted": 8, "permission-denied": 7,
                     "internal": 13, "unauthenticated": 16, "unavailable": 14]
        let cases = try fixtures("errorCases")
        #expect(cases.count == 9 && Set(cases.compactMap { $0["id"] as? String }) == Set(expected.keys))
        for row in cases {
            let id = try #require(row["id"] as? String)
            let kind = try #require(expected[id])
            let codeName = try #require(row["code"] as? String)
            let code = try #require(codes[codeName])
            let transport = CloudFunctionsTransportSpy()
            transport.error = functionsFailure(code: code, reason: row["reason"] as? String)
            let repo = CloudFunctionsBrandRequestRepository(transport: transport)
            let form = BrandRequestViewModel(initialBrandName: "모노", submitUseCase: SubmitBrandRequestUseCase(repository: repo),
                loadBrandUseCase: LoadPublicBrandUseCase(repository: BrandOperationsRepositoryFake()))
            form.websiteURL = "mono.example"
            #expect(await form.submit() == nil && form.receipt == nil)
            #expect(form.submissionErrorMessage == kind.errorDescription)
            form.dismissSubmissionError()
            #expect(form.websiteURL == "mono.example" && transport.calls.count == 1)
            await #expect(throws: kind) { try await repo.listMyBrandRequests(scope: .active, limit: 20, cursor: nil) }
        }
        for error in [functionsFailure(code: 8), functionsFailure(code: 8, reason: "FUTURE_REASON"),
                      functionsFailure(code: 7, reason: "DAILY_LIMIT_REACHED"), NSError(domain: "unrelated", code: 8)] {
            #expect(BrandRequestCloudFunctionsMapper.failure(error) != .dailyLimit)
            #expect(BrandRequestCloudFunctionsMapper.failure(error) != .requestBlocked)
        }
    }

    @Test func originalResourceExhaustedDetailsAreOptInAndOtherCallsKeepLegacyError() {
        for reason in ["DAILY_LIMIT_REACHED", "QUERY_BUDGET_EXCEEDED"] {
            let error = functionsFailure(code: 8, reason: reason)
            let original = FirebaseCloudFunctionsTransport.mapError(error, preservingDetails: true) as NSError
            #expect(original.domain == FunctionsErrorDomain && original.code == 8)
            #expect((original.userInfo[FunctionsErrorDetailsKey] as? [String: String])?["reason"] == reason)
            let legacy = FirebaseCloudFunctionsTransport.mapError(error, preservingDetails: false)
            if case CloudFunctionsTransportError.rateLimited = legacy {} else { Issue.record("기존 공통 오류를 유지해야 한다") }
        }
        let unrelated = NSError(domain: "unrelated", code: 8)
        #expect((FirebaseCloudFunctionsTransport.mapError(unrelated, preservingDetails: false) as NSError).domain == "unrelated")
    }

    @Test func emptyContinuationFailureKeepsRowsAndLastConsumedCursorForRetry() async throws {
        let transport = CloudFunctionsTransportSpy()
        let a: [String: Any] = ["createdAt": "2026-10-15T00:00:00.000Z", "requestID": "a"]
        let consumed: [String: Any] = ["createdAt": "2026-10-14T00:00:00.000Z", "requestID": "consumed-candidate"]
        transport.responses = [
            ["scope": "active", "requests": [wireRequest("a")], "nextCursor": a],
            ["scope": "active", "requests": [], "nextCursor": consumed],
            ["scope": "active", "requests": [wireRequest("b")], "nextCursor": NSNull()]
        ]
        transport.responseHandler = { _ in
            if transport.calls.count == 2 { transport.error = functionsFailure(code: 8, reason: "QUERY_BUDGET_EXCEEDED") }
            return nil
        }
        let model = historyModel(transport)
        await model.loadInitial()
        await model.loadNextPageIfNeeded(current: try #require(model.requests.first))
        #expect(model.requests.map(\.id) == ["a"] && model.canLoadNextPage)
        #expect(model.phase == .failed(try #require(BrandRequestFailure.queryBudget.errorDescription)))
        #expect(transport.calls.count == 3)
        transport.error = nil
        transport.responseHandler = nil
        await model.retry()
        #expect(model.requests.map(\.id) == ["a", "b"] && model.phase == .ready && !model.canLoadNextPage)
        #expect(transport.calls.map { $0.data["cursorRequestID"] as? String } == [nil, "a", "consumed-candidate", "consumed-candidate"])
    }

    @Test func initialEmptyPagesContinueAndRepeatedCursorFailsWithoutEnding() async {
        let transport = CloudFunctionsTransportSpy()
        let cursor: [String: Any] = ["createdAt": "2026-10-15T00:00:00.000Z", "requestID": "consumed"]
        let empty: [String: Any] = ["scope": "active", "requests": [], "nextCursor": cursor]
        transport.responses = [empty, empty, ["scope": "active", "requests": [wireRequest("next")], "nextCursor": NSNull()]]
        let model = historyModel(transport)
        await model.loadInitial()
        #expect(transport.calls.count == 2 && model.requests.isEmpty && model.canLoadNextPage)
        if case .failed = model.phase {} else { Issue.record("반복 커서를 종료로 처리하지 않아야 한다") }
        await model.retry()
        #expect(model.requests.map(\.id) == ["next"] && model.phase == .ready && !model.canLoadNextPage)
        let end = CloudFunctionsTransportSpy()
        end.responses = [empty, ["scope": "active", "requests": [], "nextCursor": NSNull()]]
        let ended = historyModel(end)
        await ended.loadInitial()
        #expect(end.calls.count == 2 && ended.phase == .ready && ended.requests.isEmpty && !ended.canLoadNextPage)
    }

    @Test func malformedNextPageRetainsRowsAndSuccessfulCursor() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [
            ["scope": "active", "requests": [wireRequest("a")],
             "nextCursor": ["createdAt": "2026-10-15T00:00:00.000Z", "requestID": "candidate"]],
            ["scope": "active", "requests": [], "nextCursor": ["requestID": "broken"]],
            ["scope": "active", "requests": [wireRequest("b")], "nextCursor": NSNull()]
        ]
        let model = historyModel(transport)
        await model.loadInitial()
        await model.loadNextPageIfNeeded(current: try #require(model.requests.first))
        #expect(model.requests.map(\.id) == ["a"] && model.canLoadNextPage)
        await model.retry()
        #expect(model.requests.map(\.id) == ["a", "b"] && !model.canLoadNextPage)
        #expect(transport.calls.dropFirst().allSatisfy { $0.data["cursorRequestID"] as? String == "candidate" })
    }

    @Test func typedPageInputsForwardValuesAndServerValidationErrors() async throws {
        let rows = try fixtures("pageInputCases")
        #expect(rows.count == 12)
        let notRepresentable = Set(["input-invalid-scope", "input-invalid-fraction", "input-invalid-string", "input-invalid-one-cursor"])
        var exercised = Set<String>()
        for row in rows {
            let id = try #require(row["id"] as? String)
            if notRepresentable.contains(id) { continue }
            let input = try #require(row["input"] as? [String: Any])
            let transport = CloudFunctionsTransportSpy()
            transport.responses = [["scope": input["scope"] as? String ?? "active", "requests": [], "nextCursor": NSNull()]]
            if let reason = row["reason"] as? String { transport.error = functionsFailure(code: 3, reason: reason) }
            let cursor = (input["cursorCreatedAt"] as? String).flatMap { date in
                (input["cursorRequestID"] as? String).map { BrandRequestPage.Cursor(createdAt: date, requestID: $0) }
            }
            let repository = CloudFunctionsBrandRequestRepository(transport: transport)
            do {
                _ = try await repository.listMyBrandRequests(scope: input["scope"] as? String == "history" ? .history : .active,
                    limit: input["limit"] as? Int ?? 20, cursor: cursor)
                #expect(row["reason"] == nil)
            } catch {
                #expect(error as? BrandRequestFailure == (row["reason"] as? String == "INVALID_CURSOR" ? .invalidCursor : .invalidInput))
            }
            #expect(transport.calls.count == 1)
            #expect(transport.calls.first?.data["limit"] as? Int == (input["limit"] as? Int ?? 20))
            #expect(transport.calls.first?.data["cursorCreatedAt"] as? String == cursor?.createdAt)
            exercised.insert(id)
        }
        #expect(exercised.count == 8 && exercised.isDisjoint(with: notRepresentable))
    }

    private func historyModel(_ transport: CloudFunctionsTransportSpy) -> MyBrandRequestsViewModel {
        .init(listUseCase: ListMyBrandRequestsUseCase(repository: CloudFunctionsBrandRequestRepository(transport: transport)),
              loadBrandUseCase: LoadPublicBrandUseCase(repository: BrandOperationsRepositoryFake()))
    }
}

private func receiptDictionary(status: String = "submitted", brandID: String? = nil) -> [String: Any] {
    ["requestID": "request", "groupID": "group", "status": status, "isDuplicate": false,
     "remainingToday": 4, "resolvedBrandID": brandID.map { $0 as Any } ?? NSNull()]
}

private func wireRequest(_ id: String, status: String = "submitted", brandID: String? = nil) -> [String: Any] {
    ["requestID": id, "groupID": "group", "brandName": "모노", "englishBrandName": NSNull(),
     "websiteURL": "https://mono.example/", "status": status,
     "resolvedBrandID": brandID.map { $0 as Any } ?? NSNull(),
     "rejectionReason": status == "rejected" ? "공식 룩북 확인 필요" as Any : NSNull(),
     "createdAt": "2026-10-15T00:00:00.000Z", "updatedAt": "2026-10-15T00:00:00.000Z"]
}

private func functionsFailure(code: Int, reason: String? = nil) -> NSError {
    var info: [String: Any] = [NSLocalizedDescriptionKey: "내부 오류 문구는 분기에 사용하지 않음"]
    if let reason { info[FunctionsErrorDetailsKey] = ["reason": reason] }
    return NSError(domain: FunctionsErrorDomain, code: code, userInfo: info)
}

private func receipt(status: BrandRequestStatus, duplicate: Bool = false, brandID: String? = nil) -> BrandRequestSubmissionReceipt {
    .init(requestID: "request", groupID: "group", status: status, isDuplicate: duplicate,
          remainingToday: 4, resolvedBrandID: brandID.map(BrandID.init(value:)))
}

private func request(_ id: String, status: BrandRequestStatus = .submitted, brandID: String? = nil) -> BrandRequest {
    .init(id: id, brandName: "모노", normalizedBrandName: "모노", englishBrandName: nil,
          normalizedEnglishBrandName: nil, groupID: "group", dedupeKey: nil, dedupeKeySource: nil,
          status: status, resolvedBrandID: brandID.map(BrandID.init(value:)), rejectionReason: nil,
          createdAt: nil, updatedAt: nil)
}

private func publicBrand() -> Brand {
    .init(id: .init(value: "public-brand"), name: "모노", englishName: "Mono", websiteURL: nil,
          lookbookArchiveURL: nil, logoThumbPath: "brands/logo", logoDetailPath: nil, logoOriginalPath: nil,
          isFeatured: false, discoveryStatus: .idle, lastDiscoveryErrorMessage: nil,
          lastDiscoveryRequestedAt: nil, lastDiscoveryCompletedAt: nil,
          metrics: .init(likeCount: 1, viewCount: 0, popularScore: 0), deletionStatus: .active,
          updatedAt: Date(timeIntervalSince1970: 0), publicationStatus: "public")
}

private final class BrandOperationsRepositoryFake: BrandRepositoryProtocol {
    var brand = publicBrand()
    var error: Error?
    var readIDs: [BrandID] = []
    func fetchBrand(brandID: BrandID) async throws -> Brand {
        readIDs.append(brandID)
        if let error { throw error }
        return brand
    }
    func fetchBrands(sort: BrandSort?, limit: Int, after: DocumentSnapshot?) async throws -> BrandPage { .init(items: [brand], last: nil) }
    func fetchFeaturedBrands(sort: BrandSort?, limit: Int, after: DocumentSnapshot?) async throws -> BrandPage { .init(items: [brand], last: nil) }
    func fetchInterestedStyleBrands(moodIDs: [String], limit: Int, after: InterestedStyleBrandCursor?) async throws -> InterestedStyleBrandPage { .init(items: [brand], nextCursor: nil) }
}

private struct BrandOperationsSeasonFake: SeasonRepositoryProtocol {
    func fetchSeason(brandID: BrandID, seasonID: SeasonID) async throws -> Season { throw LookbookContentUnavailableError.seasonUnavailable }
    func fetchSeasons(brandID: BrandID, pageSize: Int, after: DocumentSnapshot?) async throws -> SeasonPage { .init(items: [], last: nil) }
    func fetchAllSeasons(brandID: BrandID) async throws -> [Season] { [] }
}

private final class BrandOperationsSubmitFake: SubmitBrandRequestUseCaseProtocol {
    var inputs: [[String]] = []
    var results: [Result<BrandRequestSubmissionReceipt, Error>] = []
    func execute(brandName: String, websiteURL: String, englishBrandName: String?) async throws -> BrandRequestSubmissionReceipt {
        inputs.append([brandName, websiteURL, englishBrandName ?? ""])
        return try results.removeFirst().get()
    }
}

private struct BrandOperationsUserStateFake: BrandUserStateRepositoryProtocol {
    func fetchBrandUserState(userID: UserID, brandID: BrandID) async throws -> BrandUserState? { nil }
    func fetchLikedBrandUserStates(userID: UserID, limit: Int, after: DocumentSnapshot?) async throws -> BrandUserStatePage {
        .init(items: [.init(brandID: .init(value: "public-brand"), userID: userID, isLiked: true,
                            updatedAt: Date(timeIntervalSince1970: 0))], last: nil)
    }
}

@MainActor
private final class BrandOperationsHistoryFake: ListMyBrandRequestsUseCaseProtocol {
    var suspendActive = false
    var activeWasCancelled = false
    var calls: [BrandRequestListScope] = []
    var pages: [Result<BrandRequestPage, Error>] = []
    private var continuation: CheckedContinuation<BrandRequestPage, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    func waitForActive() async {
        if continuation != nil { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func finishActive() {
        continuation?.resume(returning: .init(requests: [request("late-active")], nextCursor: nil, scope: .active))
        continuation = nil
    }
    func execute(scope: BrandRequestListScope, limit: Int, cursor: BrandRequestPage.Cursor?) async throws -> BrandRequestPage {
        calls.append(scope)
        if scope == .active && suspendActive {
            let page = await withCheckedContinuation { continuation = $0; startWaiter?.resume(); startWaiter = nil }
            activeWasCancelled = Task.isCancelled
            return page
        }
        if !pages.isEmpty { return try pages.removeFirst().get() }
        return .init(requests: [request("history", status: .added)], nextCursor: nil, scope: scope)
    }
}

@MainActor
private final class BrandOperationsCoordinatorSpy: BrandRequestRouting {
    var brands: [Brand] = []
    var names: [String] = []
    func pushBrandRequest(initialBrandName: String) { names.append(initialBrandName) }
    func pushBrandDetail(brand: Brand) { brands.append(brand) }
}

private actor BrandOperationsImageSpy: BrandImageCacheProtocol {
    private(set) var paths: [String] = []
    func loadImage(path: String, maxBytes: Int) async throws -> UIImage { paths.append(path); return UIImage() }
    func storeImageData(_ data: Data, path: String) async throws {}
    func removeImage(path: String) async {}
    func prefetch(items: [(path: String, maxBytes: Int)], concurrency: Int, storePolicy: ImageCacheStorePolicy) async { paths += items.map(\.path) }
}
