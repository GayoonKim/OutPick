import Foundation

struct BrandAdminCapabilitiesResponse {
    let isTotalAdmin: Bool
    let roles: [String]
    let ownedBrandIDs: [String]
    let adminBrandIDs: [String]
}

protocol BrandAdminCapabilitiesCalling {
    func getBrandAdminCapabilities() async throws -> BrandAdminCapabilitiesResponse
}
