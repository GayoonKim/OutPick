//
//  BrandDetailViewModel.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

@MainActor
final class BrandDetailViewModel: ObservableObject {
    @Published private(set) var seasons: [Season] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    private let initialPrefetchCount: Int
    private let lookAheadPrefetchCount: Int
    private let prefetchConcurrency: Int

    private var loadedBrandID: BrandID?
    private var isRequesting: Bool = false
    private var prefetchedSeasonImagePaths = Set<String>()

    init(
        initialPrefetchCount: Int = 12,
        lookAheadPrefetchCount: Int = 8,
        prefetchConcurrency: Int = 6
    ) {
        self.initialPrefetchCount = initialPrefetchCount
        self.lookAheadPrefetchCount = lookAheadPrefetchCount
        self.prefetchConcurrency = prefetchConcurrency
    }

    /// 최초 진입 시 중복 로드 방지
    func loadContentsIfNeeded(
        brandID: BrandID,
        seasonRepository: any SeasonRepositoryProtocol,
        brandImageCache: any BrandImageCacheProtocol,
        maxBytes: Int
    ) async {
        if loadedBrandID == brandID, !seasons.isEmpty { return }
        await fetchAll(
            brandID: brandID,
            seasonRepository: seasonRepository,
            force: false,
            brandImageCache: brandImageCache,
            maxBytes: maxBytes
        )
    }

    /// 시즌 추가 후(시트 닫힘 등) 강제 새로고침
    func refreshContents(
        brandID: BrandID,
        seasonRepository: any SeasonRepositoryProtocol,
        brandImageCache: any BrandImageCacheProtocol,
        maxBytes: Int
    ) async {
        await fetchAll(
            brandID: brandID,
            seasonRepository: seasonRepository,
            force: true,
            brandImageCache: brandImageCache,
            maxBytes: maxBytes
        )
    }

    private func fetchAll(
        brandID: BrandID,
        seasonRepository: any SeasonRepositoryProtocol,
        force: Bool,
        brandImageCache: any BrandImageCacheProtocol,
        maxBytes: Int
    ) async {
        if isRequesting { return }
        isRequesting = true
        defer { isRequesting = false }

        if !force, loadedBrandID == brandID, !seasons.isEmpty {
            return
        }

        loadedBrandID = brandID
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetched = try await seasonRepository.fetchAllSeasons(brandID: brandID)
            prefetchedSeasonImagePaths.removeAll()
            let sorted = fetched.sorted(by: Season.defaultSort)
            let initialTargets = makePrefetchTargets(
                from: sorted,
                startingAt: 0,
                count: initialPrefetchCount,
                maxBytes: maxBytes
            )
            await prefetchImmediately(
                items: initialTargets,
                brandImageCache: brandImageCache
            )
            seasons = sorted
        } catch {
            seasons = []
            errorMessage = "시즌을 불러오지 못했습니다."
            prefetchedSeasonImagePaths.removeAll()
        }
    }

    func prefetchInitialSeasonCoversIfNeeded(
        brandImageCache: any BrandImageCacheProtocol,
        maxBytes: Int
    ) {
        let targets = makePrefetchTargets(startingAt: 0, count: initialPrefetchCount, maxBytes: maxBytes)
        schedulePrefetch(items: targets, brandImageCache: brandImageCache)
    }

    func seasonDidAppear(
        seasonID: SeasonID,
        brandImageCache: any BrandImageCacheProtocol,
        maxBytes: Int
    ) {
        guard let currentIndex = seasons.firstIndex(where: { $0.id == seasonID }) else {
            return
        }

        let targets = makePrefetchTargets(
            startingAt: currentIndex + 1,
            count: lookAheadPrefetchCount,
            maxBytes: maxBytes
        )
        schedulePrefetch(items: targets, brandImageCache: brandImageCache)
    }

    private func makePrefetchTargets(
        from seasons: [Season],
        startingAt startIndex: Int,
        count: Int,
        maxBytes: Int
    ) -> [(path: String, maxBytes: Int)] {
        guard startIndex < seasons.count, count > 0 else {
            return []
        }

        let endIndex = min(seasons.count, startIndex + count)
        var targets: [(path: String, maxBytes: Int)] = []

        for season in seasons[startIndex..<endIndex] {
            guard let path = preferredPrefetchPath(for: season) else { continue }
            guard prefetchedSeasonImagePaths.contains(path) == false else { continue }

            prefetchedSeasonImagePaths.insert(path)
            targets.append((path: path, maxBytes: maxBytes))
        }

        return targets
    }

    private func makePrefetchTargets(
        startingAt startIndex: Int,
        count: Int,
        maxBytes: Int
    ) -> [(path: String, maxBytes: Int)] {
        makePrefetchTargets(
            from: seasons,
            startingAt: startIndex,
            count: count,
            maxBytes: maxBytes
        )
    }

    private func schedulePrefetch(
        items: [(path: String, maxBytes: Int)],
        brandImageCache: any BrandImageCacheProtocol
    ) {
        guard !items.isEmpty else { return }
        let concurrency = prefetchConcurrency

        Task(priority: .utility) {
            await brandImageCache.prefetch(
                items: items,
                concurrency: concurrency,
                storePolicy: .memoryOnly
            )
        }
    }

    private func prefetchImmediately(
        items: [(path: String, maxBytes: Int)],
        brandImageCache: any BrandImageCacheProtocol
    ) async {
        guard !items.isEmpty else { return }

        await brandImageCache.prefetch(
            items: items,
            concurrency: prefetchConcurrency,
            storePolicy: .memoryOnly
        )
    }

    private func preferredPrefetchPath(for season: Season) -> String? {
        let candidates = [season.coverThumbPath, season.coverPath]

        for candidate in candidates {
            guard let candidate else { continue }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return trimmed
            }
        }

        return nil
    }
}
