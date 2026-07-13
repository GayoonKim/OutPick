import Foundation
import Testing
@testable import OutPick

struct BrandAdminCapabilitiesCloudFunctionsClientTests {
    @Test func loadsCapabilitiesWithEmptyPayload() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [[
            "isTotalAdmin": true,
            "roles": ["owner"],
            "ownedBrandIDs": ["brand-1"],
            "adminBrandIDs": ["brand-2"]
        ]]
        let client = BrandAdminCapabilitiesCloudFunctionsClient(transport: transport)

        let response = try await client.getBrandAdminCapabilities()

        #expect(transport.calls.count == 1)
        #expect(transport.calls[0].name == "getBrandAdminCapabilities")
        #expect(transport.calls[0].data.isEmpty)
        #expect(response.isTotalAdmin)
        #expect(response.roles == ["owner"])
        #expect(response.ownedBrandIDs == ["brand-1"])
        #expect(response.adminBrandIDs == ["brand-2"])
    }

    @Test func appliesExistingDefaultsForMissingOptionalCapabilityFields() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [[:]]
        let client = BrandAdminCapabilitiesCloudFunctionsClient(transport: transport)

        let response = try await client.getBrandAdminCapabilities()

        #expect(response.isTotalAdmin == false)
        #expect(response.roles.isEmpty)
        #expect(response.ownedBrandIDs.isEmpty)
        #expect(response.adminBrandIDs.isEmpty)
    }
}
