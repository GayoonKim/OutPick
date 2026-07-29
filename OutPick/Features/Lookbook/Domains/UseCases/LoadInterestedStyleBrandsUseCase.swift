import Foundation

struct InterestedStyleBrandCursor: Equatable {
    let likeCount: Int
    let brandID: BrandID
}

struct InterestedStyleBrandPage: Equatable {
    let items: [Brand]
    let nextCursor: InterestedStyleBrandCursor?
}

protocol LoadInterestedStyleBrandsUseCaseProtocol {
    func execute(
        moodIDs: [String],
        limit: Int,
        after cursor: InterestedStyleBrandCursor?
    ) async throws -> InterestedStyleBrandPage
}

struct LoadInterestedStyleBrandsUseCase: LoadInterestedStyleBrandsUseCaseProtocol {
    private let repository: BrandRepositoryProtocol

    init(repository: BrandRepositoryProtocol) {
        self.repository = repository
    }

    func execute(
        moodIDs: [String],
        limit: Int,
        after cursor: InterestedStyleBrandCursor?
    ) async throws -> InterestedStyleBrandPage {
        let normalizedMoodIDs = normalized(moodIDs)
        guard normalizedMoodIDs.isEmpty == false, limit > 0 else {
            return InterestedStyleBrandPage(items: [], nextCursor: nil)
        }

        let page = try await repository.fetchInterestedStyleBrands(
            moodIDs: normalizedMoodIDs,
            limit: limit,
            after: cursor
        )

        var seen = Set<BrandID>()
        let items = page.items
            .filter { $0.isVisibleToUsers && seen.insert($0.id).inserted }
            .sorted(by: Self.isOrderedBefore)

        return InterestedStyleBrandPage(
            items: items,
            nextCursor: page.nextCursor
        )
    }

    private func normalized(_ moodIDs: [String]) -> [String] {
        var seen = Set<String>()
        return moodIDs.compactMap { rawValue in
            let moodID = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard moodID.isEmpty == false, seen.insert(moodID).inserted else {
                return nil
            }
            return moodID
        }
    }

    private static func isOrderedBefore(_ lhs: Brand, _ rhs: Brand) -> Bool {
        if lhs.metrics.likeCount != rhs.metrics.likeCount {
            return lhs.metrics.likeCount > rhs.metrics.likeCount
        }
        return lhs.id.value < rhs.id.value
    }
}
