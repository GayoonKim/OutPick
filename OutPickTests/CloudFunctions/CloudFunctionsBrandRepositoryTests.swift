import Foundation
import Testing
@testable import OutPick

struct CloudFunctionsBrandRepositoryTests {
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
            ["brandID": "brand-1"],
            ["brand": brand],
            ["brandID": "brand-1"],
            managerReceipt,
            managerReceipt,
            ["brands": [brand]]
        ]
        let store = CloudFunctionsBrandStore(transport: transport)
        let search = CloudFunctionsBrandSearchRepository(transport: transport)

        _ = try await store.createBrand(
            name: "Brand",
            englishName: nil,
            isFeatured: true,
            websiteURL: nil,
            lookbookArchiveURL: "https://archive.example.com"
        )
        _ = try await store.updateBrand(
            brandID: BrandID(value: "brand-1"),
            name: "Brand",
            englishName: nil,
            websiteURL: nil,
            lookbookArchiveURL: nil,
            isFeatured: nil
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
        #expect(transport.calls[0].data["lookbookArchiveURL"] as? String == "https://archive.example.com")
        #expect(transport.calls[1].data["englishName"] is NSNull)
        #expect(transport.calls[1].data["websiteURL"] as? String == "")
        #expect(transport.calls[1].data["isFeatured"] == nil)
        #expect(transport.calls[2].data["logoThumbPath"] as? String == "thumb.jpg")
        #expect(transport.calls[2].data["logoDetailPath"] == nil)
        #expect(removed.removed)
        #expect(brands.map(\.id.value) == ["brand-1"])
    }

    private static var brandDictionary: [String: Any] {
        [
            "brandID": "brand-1",
            "name": "Brand",
            "metrics": ["likeCount": 1, "viewCount": 2, "popularScore": 3.0]
        ]
    }
}
