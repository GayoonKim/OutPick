import Foundation
import Testing
@testable import OutPick

struct CloudFunctionsBrandRepositoryTests {
    @Test func coversPublicSearchCallableContract() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [["brands": [[
            "brandID": "brand-1",
            "name": "Brand",
            "metrics": ["likeCount": 1, "viewCount": 2, "popularScore": 3.0]
        ]]]]
        let search = CloudFunctionsBrandSearchRepository(transport: transport)
        let brands = try await search.searchBrands(query: "Bra", limit: 20)

        #expect(transport.calls.map(\.name) == ["searchBrands"])
        #expect(transport.calls[0].data["query"] as? String == "Bra")
        #expect(transport.calls[0].data["limit"] as? Int == 20)
        #expect(brands.map(\.id.value) == ["brand-1"])
    }
}
