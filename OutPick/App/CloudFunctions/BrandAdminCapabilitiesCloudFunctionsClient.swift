import Foundation

final class BrandAdminCapabilitiesCloudFunctionsClient: BrandAdminCapabilitiesCalling {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting) {
        self.transport = transport
    }

    func getBrandAdminCapabilities() async throws -> BrandAdminCapabilitiesResponse {
        let response = try await transport.call(
            "getBrandAdminCapabilities",
            data: [:]
        )
        let decoder = CloudFunctionResponseDecoder(dictionary: response)

        return BrandAdminCapabilitiesResponse(
            isTotalAdmin: decoder.optionalBool("isTotalAdmin") ?? false,
            roles: decoder.stringArray("roles"),
            ownedBrandIDs: decoder.stringArray("ownedBrandIDs"),
            adminBrandIDs: decoder.stringArray("adminBrandIDs")
        )
    }
}
