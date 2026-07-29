import Combine
import Foundation

@MainActor
final class InterestedStyleBrandListViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case ready
        case empty
        case failed(String)
    }

    @Published private(set) var phase: Phase
    @Published private(set) var brands: [Brand]
    @Published private(set) var isLoadingNext = false
    @Published private(set) var loadMoreErrorMessage: String?

    let brandImageCache: any BrandImageCacheProtocol

    private let loadUseCase: any LoadInterestedStyleBrandsUseCaseProtocol
    private let stylePreferenceStore: CurrentUserStylePreferenceStore
    private let pageSize: Int
    private var nextCursor: InterestedStyleBrandCursor?
    private var requestedCursor: InterestedStyleBrandCursor?
    private var generation = 0
    private var cancellables = Set<AnyCancellable>()

    init(
        initialBrands: [Brand],
        initialCursor: InterestedStyleBrandCursor?,
        loadUseCase: any LoadInterestedStyleBrandsUseCaseProtocol,
        stylePreferenceStore: CurrentUserStylePreferenceStore,
        brandImageCache: any BrandImageCacheProtocol,
        pageSize: Int = 20
    ) {
        brands = initialBrands
        nextCursor = initialCursor
        phase = initialBrands.isEmpty ? .empty : .ready
        self.loadUseCase = loadUseCase
        self.stylePreferenceStore = stylePreferenceStore
        self.brandImageCache = brandImageCache
        self.pageSize = max(1, pageSize)
        bindStylePreferenceStore()
    }

    func refresh() async {
        generation += 1
        let currentGeneration = generation
        let moodIDs = stylePreferenceStore.selectedMoodIDs

        guard moodIDs.isEmpty == false else {
            brands = []
            nextCursor = nil
            requestedCursor = nil
            phase = .empty
            return
        }

        phase = .loading
        loadMoreErrorMessage = nil

        do {
            let page = try await loadUseCase.execute(
                moodIDs: moodIDs,
                limit: pageSize,
                after: nil
            )
            guard currentGeneration == generation else { return }

            brands = deduplicated(page.items)
            nextCursor = page.nextCursor
            requestedCursor = nil
            phase = brands.isEmpty ? .empty : .ready
        } catch {
            guard currentGeneration == generation else { return }
            phase = .failed("관심 스타일 브랜드를 불러오지 못했어요")
        }
    }

    func loadNextPageIfNeeded(current brand: Brand) async {
        guard phase == .ready,
              brands.last?.id == brand.id,
              isLoadingNext == false,
              let cursor = nextCursor,
              requestedCursor != cursor else {
            return
        }

        isLoadingNext = true
        loadMoreErrorMessage = nil
        let currentGeneration = generation
        var cursorToLoad: InterestedStyleBrandCursor? = cursor
        requestedCursor = cursor
        defer { isLoadingNext = false }

        do {
            while let currentCursor = cursorToLoad {
                let page = try await loadUseCase.execute(
                    moodIDs: stylePreferenceStore.selectedMoodIDs,
                    limit: pageSize,
                    after: currentCursor
                )
                guard currentGeneration == generation else { return }

                let existingIDs = Set(brands.map(\.id))
                let newItems = page.items.filter { existingIDs.contains($0.id) == false }
                nextCursor = page.nextCursor

                if newItems.isEmpty == false {
                    brands.append(contentsOf: deduplicated(newItems))
                    requestedCursor = nil
                    return
                }

                guard let followingCursor = page.nextCursor,
                      followingCursor != currentCursor else {
                    requestedCursor = nil
                    return
                }
                cursorToLoad = followingCursor
                requestedCursor = followingCursor
            }
            requestedCursor = nil
        } catch {
            guard currentGeneration == generation else { return }
            requestedCursor = nil
            loadMoreErrorMessage = "다음 브랜드를 불러오지 못했어요"
        }
    }

    func retryLoadMore() async {
        guard let last = brands.last else {
            await refresh()
            return
        }
        await loadNextPageIfNeeded(current: last)
    }

    private func bindStylePreferenceStore() {
        stylePreferenceStore.$selectedMoodIDs
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refresh()
                }
            }
            .store(in: &cancellables)
    }

    private func deduplicated(_ brands: [Brand]) -> [Brand] {
        var seen = Set<BrandID>()
        return brands.filter { seen.insert($0.id).inserted }
    }
}
