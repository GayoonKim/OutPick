import Foundation

protocol LoadPublicBrandUseCaseProtocol {
    func execute(brandID: BrandID) async throws -> Brand
}

struct LoadPublicBrandUseCase: LoadPublicBrandUseCaseProtocol {
    let repository: any BrandRepositoryProtocol

    func execute(brandID: BrandID) async throws -> Brand {
        let brand = try await repository.fetchBrand(brandID: brandID)
        guard brand.isVisibleToUsers else { throw LookbookContentUnavailableError.brandUnavailable }
        return brand
    }
}
