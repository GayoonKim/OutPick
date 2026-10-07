import Foundation
import Testing
@testable import OutPick

struct CloudFunctionsBrandRepositoryTests {
    @Test func requestStoreFailurePreventsBrandCreationRequest() async throws {
        let transport = CloudFunctionsTransportSpy()
        let store = CloudFunctionsBrandStore(
            transport: transport,
            requestStore: UnavailableLookbookImportRequestStore(),
            currentUserUIDProvider: { "user-1" }
        )

        do {
            _ = try await store.createBrand(
                name: "Brand",
                englishName: nil,
                isFeatured: false,
                websiteURL: nil,
                lookbookArchiveURL: "https://archive.example.com",
                moodIDs: []
            )
            Issue.record("요청 기록 저장 실패 후 브랜드 생성 요청이 전송되면 안 됩니다.")
        } catch {
            #expect(transport.calls.isEmpty)
        }
    }

    @Test func coversBrandStoreAndSearchCallableContracts() async throws {
        let transport = CloudFunctionsTransportSpy()
        let brand = Self.brandDictionary
        let managerReceipt: [String: Any] = [
            "brandID": "brand-1",
            "uid": "user-1",
            "email": "manager@example.com",
            "role": "admin"
        ]
        transport.responses = [
            ["brandID": "brand-1", "discoveryJobID": "discovery-1", "batchID": "batch-1"],
            ["brand": brand],
            ["brandID": "brand-1"],
            managerReceipt,
            managerReceipt,
            ["brands": [brand]]
        ]
        let requestStore = GRDBLookbookImportRequestStore(database: try TemporaryAppDatabase.make())
        let store = CloudFunctionsBrandStore(
            transport: transport,
            requestStore: requestStore,
            currentUserUIDProvider: { "user-1" },
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let search = CloudFunctionsBrandSearchRepository(transport: transport)

        let creationReceipt = try await store.createBrand(
            name: "Brand",
            englishName: nil,
            isFeatured: true,
            websiteURL: nil,
            lookbookArchiveURL: "https://archive.example.com",
            moodIDs: ["minimal"]
        )
        _ = try await store.updateBrand(
            brandID: BrandID(value: "brand-1"),
            name: "Brand",
            englishName: nil,
            websiteURL: nil,
            lookbookArchiveURL: nil,
            isFeatured: nil,
            moodIDs: []
        )
        try await store.updateLogoPaths(
            docID: "brand-1",
            logoThumbPath: "thumb.jpg",
            logoDetailPath: nil
        )
        _ = try await store.addBrandManager(
            brandID: BrandID(value: "brand-1"),
            email: "manager@example.com",
            role: .admin
        )
        let removed = try await store.removeBrandManager(
            brandID: BrandID(value: "brand-1"),
            email: "manager@example.com",
            role: .admin
        )
        let brands = try await search.searchBrands(query: "Bra", limit: 20)

        #expect(transport.calls.map(\.name) == [
            "createBrand", "updateBrand", "updateBrandLogoPaths",
            "addBrandManager", "removeBrandManager", "searchBrands"
        ])
        #expect(transport.calls[0].data["englishName"] == nil)
        #expect(transport.calls[0].data["queueContractVersion"] as? Int == 1)
        #expect(transport.calls[0].data["requestID"] as? String == creationReceipt.requestID)
        #expect(transport.calls[0].data["requestCreatedAt"] as? Int64 == 1_800_000_000_000)
        #expect(transport.calls[0].data["lookbookArchiveURL"] as? String == "https://archive.example.com")
        #expect(transport.calls[0].data["moodIDs"] as? [String] == ["minimal"])
        #expect(transport.calls[1].data["englishName"] is NSNull)
        #expect(transport.calls[1].data["websiteURL"] as? String == "")
        #expect(transport.calls[1].data["isFeatured"] == nil)
        #expect(transport.calls[1].data["moodIDs"] as? [String] == [])
        #expect(transport.calls[2].data["logoThumbPath"] as? String == "thumb.jpg")
        #expect(transport.calls[2].data["logoDetailPath"] == nil)
        #expect(removed.removed)
        #expect(brands.map(\.id.value) == ["brand-1"])
        let storedRequests = try await requestStore.fetchUnsettled(ownerUID: "user-1", brandID: "brand-1")
        let storedRequest = storedRequests.first
        #expect(storedRequest?.requestID == creationReceipt.requestID)
        #expect(storedRequest?.batchID == "batch-1")
        #expect(storedRequest?.localState == .accepted)
    }

    private static var brandDictionary: [String: Any] {
        [
            "brandID": "brand-1",
            "name": "Brand",
            "metrics": ["likeCount": 1, "viewCount": 2, "popularScore": 3.0]
        ]
    }
}
