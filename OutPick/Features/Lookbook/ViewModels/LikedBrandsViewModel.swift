//
//  LikedBrandsViewModel.swift
//  OutPick
//
//  Created by Codex on 5/26/26.
//

import Foundation
import FirebaseFirestore

@MainActor
final class LikedBrandsViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case empty
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var items: [LikedBrandListItem] = []

    let brandImageCache: any BrandImageCacheProtocol

    private let useCase: any LoadLikedBrandsUseCaseProtocol
    private let brandInteractionStore: any BrandInteractionManaging
    private let currentUserIDProvider: any CurrentUserIDProviding
    private let pageSize: Int

    private var lastDocument: DocumentSnapshot?
    private var isLoadingInitial = false
    private var isLoadingNext = false
    private var canLoadMore = true
    private var didLoadInitial = false
    private var brandInvalidationTasks: [BrandID: Task<Void, Never>] = [:]

    init(
        useCase: any LoadLikedBrandsUseCaseProtocol,
        brandInteractionStore: any BrandInteractionManaging,
        currentUserIDProvider: any CurrentUserIDProviding,
        brandImageCache: any BrandImageCacheProtocol,
        pageSize: Int = 20
    ) {
        self.useCase = useCase
        self.brandInteractionStore = brandInteractionStore
        self.currentUserIDProvider = currentUserIDProvider
        self.brandImageCache = brandImageCache
        self.pageSize = pageSize
    }

    deinit {
        for task in brandInvalidationTasks.values {
            task.cancel()
        }
    }

    func refreshForActivation() async {
        if didLoadInitial {
            await loadLikedBrands(showsLoading: false, clearsItemsOnFailure: false)
        } else {
            await reload()
        }
    }

    func loadInitialIfNeeded() async {
        guard didLoadInitial == false else { return }
        await reload()
    }

    func reload() async {
        await loadLikedBrands(showsLoading: true, clearsItemsOnFailure: true)
    }

    private func loadLikedBrands(
        showsLoading: Bool,
        clearsItemsOnFailure: Bool
    ) async {
        guard isLoadingInitial == false else { return }
        guard let userID = currentUserIDProvider.currentUserID else {
            phase = .failed("로그인이 필요합니다.")
            items = []
            return
        }

        isLoadingInitial = true
        defer { isLoadingInitial = false }

        if showsLoading {
            phase = .loading
        }
        lastDocument = nil
        canLoadMore = true

        do {
            let page = try await useCase.execute(
                userID: userID,
                limit: pageSize,
                after: nil
            )
            items = page.items
            lastDocument = page.last
            canLoadMore = page.last != nil
            didLoadInitial = true
            seedInteractionStore(items: page.items)
            resetBrandInvalidationSubscriptions(with: page.items.map { $0.id })
            phase = items.isEmpty ? .empty : .ready
        } catch {
            if clearsItemsOnFailure || items.isEmpty {
                items = []
                phase = .failed("좋아요한 브랜드를 불러오지 못했습니다.")
            }
        }
    }

    func loadNextPageIfNeeded(current item: LikedBrandListItem) async {
        guard phase == .ready else { return }
        guard canLoadMore, isLoadingNext == false else { return }
        guard items.last?.id == item.id else { return }
        guard let userID = currentUserIDProvider.currentUserID else { return }
        guard let lastDocument else { return }

        isLoadingNext = true
        defer { isLoadingNext = false }

        do {
            let page = try await useCase.execute(
                userID: userID,
                limit: pageSize,
                after: lastDocument
            )
            self.lastDocument = page.last
            canLoadMore = page.last != nil
            let appendedItems = appendDeduplicated(page.items)
            seedInteractionStore(items: page.items)
            subscribeToBrandInvalidationsIfNeeded(for: appendedItems.map { $0.id })
        } catch {
            canLoadMore = false
        }
    }

    @discardableResult
    private func appendDeduplicated(_ newItems: [LikedBrandListItem]) -> [LikedBrandListItem] {
        let existingIDs = Set(items.map(\.id))
        let deduplicatedItems = newItems.filter { existingIDs.contains($0.id) == false }
        items.append(contentsOf: deduplicatedItems)
        return deduplicatedItems
    }

    private func seedInteractionStore(items: [LikedBrandListItem]) {
        for item in items {
            brandInteractionStore.seedBrand(item.brand, userState: item.userState)
        }
    }

    private func resetBrandInvalidationSubscriptions(with brandIDs: [BrandID]) {
        cancelAllBrandInvalidationSubscriptions()
        subscribeToBrandInvalidationsIfNeeded(for: brandIDs)
    }

    private func subscribeToBrandInvalidationsIfNeeded(for brandIDs: [BrandID]) {
        let newBrandIDs = Set(brandIDs).subtracting(brandInvalidationTasks.keys)
        guard newBrandIDs.isEmpty == false else { return }

        for brandID in newBrandIDs {
            let brandInteractionStore = brandInteractionStore
            brandInvalidationTasks[brandID] = Task { [weak self, brandInteractionStore, brandID] in
                let stream = brandInteractionStore.brandStateInvalidationStream(for: [brandID])
                for await invalidatedBrandID in stream {
                    guard invalidatedBrandID == brandID,
                          let state = brandInteractionStore.brandState(for: brandID) else { continue }
                    self?.applyInteractionState(state)
                }
            }
        }
    }

    private func cancelBrandInvalidationSubscription(for brandID: BrandID) {
        brandInvalidationTasks[brandID]?.cancel()
        brandInvalidationTasks[brandID] = nil
    }

    private func cancelAllBrandInvalidationSubscriptions() {
        for task in brandInvalidationTasks.values {
            task.cancel()
        }
        brandInvalidationTasks.removeAll()
    }

    private func cancelSubscriptionsForNonVisibleBrands() {
        let visibleBrandIDs = Set(items.map(\.id))
        let staleBrandIDs = Set(brandInvalidationTasks.keys).subtracting(visibleBrandIDs)
        for brandID in staleBrandIDs {
            cancelBrandInvalidationSubscription(for: brandID)
        }
    }

    private func applyInteractionState(_ state: BrandInteractionState) {
        guard let index = items.firstIndex(where: { $0.id == state.brandID }) else { return }
        guard state.userState?.isLiked == true else {
            items.remove(at: index)
            cancelBrandInvalidationSubscription(for: state.brandID)
            cancelSubscriptionsForNonVisibleBrands()
            if items.isEmpty {
                phase = .empty
            }
            return
        }

        let current = items[index]
        let updatedBrand = Brand(
            id: current.brand.id,
            name: current.brand.name,
            websiteURL: current.brand.websiteURL,
            lookbookArchiveURL: current.brand.lookbookArchiveURL,
            logoThumbPath: current.brand.logoThumbPath,
            logoDetailPath: current.brand.logoDetailPath,
            logoOriginalPath: current.brand.logoOriginalPath,
            isFeatured: current.brand.isFeatured,
            discoveryStatus: current.brand.discoveryStatus,
            lastDiscoveryErrorMessage: current.brand.lastDiscoveryErrorMessage,
            lastDiscoveryRequestedAt: current.brand.lastDiscoveryRequestedAt,
            lastDiscoveryCompletedAt: current.brand.lastDiscoveryCompletedAt,
            metrics: state.metrics,
            updatedAt: current.brand.updatedAt
        )
        items[index] = LikedBrandListItem(
            brand: updatedBrand,
            userState: state.userState ?? current.userState
        )
    }
}
