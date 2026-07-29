import FirebaseFirestore
import Foundation
import Testing
@testable import OutPick

struct LoadInterestedStyleBrandsUseCaseTests {
    @Test
    func emptyMoodIDsReturnsEmptyWithoutRepositoryCall() async throws {
        let repository = InterestedBrandRepositoryFake(pages: [])
        let useCase = LoadInterestedStyleBrandsUseCase(repository: repository)

        let result = try await useCase.execute(
            moodIDs: [" ", ""],
            limit: 10,
            after: nil
        )

        #expect(result == InterestedStyleBrandPage(items: [], nextCursor: nil))
        #expect(repository.requests.isEmpty)
    }

    @Test
    func normalizesInputAndReturnsDeterministicVisibleOrder() async throws {
        let low = interestedBrand("brand-b", likeCount: 2)
        let highB = interestedBrand("brand-c", likeCount: 9)
        let highA = interestedBrand("brand-a", likeCount: 9)
        let hidden = interestedBrand(
            "hidden",
            likeCount: 100,
            deletionStatus: .deletionRequested
        )
        let repository = InterestedBrandRepositoryFake(pages: [
            InterestedStyleBrandPage(
                items: [low, highB, highA, highA, hidden],
                nextCursor: InterestedStyleBrandCursor(
                    likeCount: 2,
                    brandID: low.id
                )
            )
        ])
        let useCase = LoadInterestedStyleBrandsUseCase(repository: repository)

        let result = try await useCase.execute(
            moodIDs: [" minimal ", "street", "minimal"],
            limit: 10,
            after: nil
        )

        #expect(repository.requests.first?.moodIDs == ["minimal", "street"])
        #expect(result.items.map(\.id.value) == ["brand-a", "brand-c", "brand-b"])
        #expect(result.nextCursor?.brandID == low.id)
    }
}

private final class InterestedBrandRepositoryFake: BrandRepositoryProtocol {
    struct Request {
        let moodIDs: [String]
        let limit: Int
        let cursor: InterestedStyleBrandCursor?
    }

    private var pages: [InterestedStyleBrandPage]
    private(set) var requests: [Request] = []

    init(pages: [InterestedStyleBrandPage]) {
        self.pages = pages
    }

    func fetchInterestedStyleBrands(
        moodIDs: [String],
        limit: Int,
        after cursor: InterestedStyleBrandCursor?
    ) async throws -> InterestedStyleBrandPage {
        requests.append(Request(moodIDs: moodIDs, limit: limit, cursor: cursor))
        return pages.isEmpty
            ? InterestedStyleBrandPage(items: [], nextCursor: nil)
            : pages.removeFirst()
    }

    func fetchBrand(brandID: BrandID) async throws -> Brand {
        throw InterestedBrandTestError.unused
    }

    func fetchBrands(
        sort: BrandSort?,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> BrandPage {
        throw InterestedBrandTestError.unused
    }

    func fetchFeaturedBrands(
        sort: BrandSort?,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> BrandPage {
        throw InterestedBrandTestError.unused
    }
}

private enum InterestedBrandTestError: Error {
    case unused
}

private func interestedBrand(
    _ id: String,
    likeCount: Int,
    deletionStatus: BrandDeletionStatus = .active
) -> Brand {
    Brand(
        id: BrandID(value: id),
        name: id,
        englishName: nil,
        websiteURL: nil,
        lookbookArchiveURL: nil,
        logoThumbPath: nil,
        logoDetailPath: nil,
        logoOriginalPath: nil,
        isFeatured: false,
        moodIDs: ["minimal"],
        discoveryStatus: .idle,
        lastDiscoveryErrorMessage: nil,
        lastDiscoveryRequestedAt: nil,
        lastDiscoveryCompletedAt: nil,
        metrics: BrandMetrics(
            likeCount: likeCount,
            viewCount: 0,
            popularScore: 0
        ),
        deletionStatus: deletionStatus,
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}
