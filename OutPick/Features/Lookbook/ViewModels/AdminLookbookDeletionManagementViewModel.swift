//
//  AdminLookbookDeletionManagementViewModel.swift
//  OutPick
//
//  Created by Codex on 7/7/26.
//

import Foundation
import Combine

enum AdminLookbookDeletionManagementTab: String, CaseIterable, Identifiable {
    case selection
    case requests

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selection: return "삭제"
        case .requests: return "삭제 요청 목록"
        }
    }
}

@MainActor
final class AdminLookbookDeletionManagementViewModel: ObservableObject {
    @Published var selectedTab: AdminLookbookDeletionManagementTab = .selection
    @Published var searchText: String = ""
    @Published private(set) var searchResults: [Brand] = []
    @Published private(set) var selectedBrand: Brand?
    @Published private(set) var seasons: [Season] = []
    @Published private(set) var expandedSeason: Season?
    @Published private(set) var posts: [LookbookPost] = []
    @Published private(set) var deletionRequests: [LookbookDeletionRequest] = []
    @Published private(set) var selectedSeasonIDs: Set<SeasonID> = []
    @Published private(set) var selectedPostIDs: Set<PostID> = []
    @Published var reasonText: String = ""
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var isLoadingBrandContent: Bool = false
    @Published private(set) var isLoadingPosts: Bool = false
    @Published private(set) var isLoadingMorePosts: Bool = false
    @Published private(set) var isLoadingRequests: Bool = false
    @Published private(set) var mutationKey: String?
    @Published var message: String?

    private enum FeedbackDismissDelay {
        static let result: UInt64 = 2_400_000_000
        static let failure: UInt64 = 4_500_000_000
    }

    private let brandRepository: any BrandRepositoryProtocol
    private let searchUseCase: any SearchBrandsUseCaseProtocol
    private let seasonRepository: any SeasonRepositoryProtocol
    private let postRepository: any PostRepositoryProtocol
    private let deletionRepository: any LookbookDeletionRepositoryProtocol
    private let isBrandScoped: Bool
    private let postPageSize: Int = 24
    private var nextPostCursor: PageCursor?
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private var messageDismissTask: Task<Void, Never>?

    init(
        initialBrand: Brand? = nil,
        brandRepository: any BrandRepositoryProtocol,
        searchUseCase: any SearchBrandsUseCaseProtocol,
        seasonRepository: any SeasonRepositoryProtocol,
        postRepository: any PostRepositoryProtocol,
        deletionRepository: any LookbookDeletionRepositoryProtocol
    ) {
        self.selectedBrand = initialBrand
        self.isBrandScoped = initialBrand != nil
        self.brandRepository = brandRepository
        self.searchUseCase = searchUseCase
        self.seasonRepository = seasonRepository
        self.postRepository = postRepository
        self.deletionRepository = deletionRepository
        bindSearchText()
    }

    var selectedBrandID: BrandID? {
        selectedBrand?.id
    }

    var shouldShowBrandSearch: Bool {
        isBrandScoped == false
    }

    var canClearSelectedBrand: Bool {
        isBrandScoped == false && selectedBrand != nil
    }

    var hasMorePosts: Bool {
        nextPostCursor != nil
    }

    var normalizedReason: String? {
        let trimmed = reasonText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func loadInitialContent(isTotalAdmin: Bool) async {
        await reloadDeletionRequests(isTotalAdmin: isTotalAdmin)
        guard selectedBrand != nil else { return }
        await reloadBrandContent(isTotalAdmin: isTotalAdmin)
    }

    func selectTab(_ tab: AdminLookbookDeletionManagementTab, isTotalAdmin: Bool) async {
        selectedTab = tab
        if tab == .requests {
            await reloadDeletionRequests(isTotalAdmin: isTotalAdmin)
        }
    }

    func selectBrand(_ brand: Brand, isTotalAdmin: Bool) async {
        selectedBrand = brand
        resetSelectionState()
        searchText = ""
        searchResults = []
        message = nil
        await reloadBrandContent(isTotalAdmin: isTotalAdmin)
    }

    func clearSelectedBrand(isTotalAdmin: Bool) async {
        guard canClearSelectedBrand else { return }
        selectedBrand = nil
        seasons = []
        posts = []
        resetSelectionState()
        await reloadDeletionRequests(isTotalAdmin: isTotalAdmin)
    }

    func clearSearch() {
        searchText = ""
        searchResults = []
    }

    func reloadBrandContent(isTotalAdmin: Bool) async {
        guard let brandID = selectedBrand?.id else {
            await reloadDeletionRequests(isTotalAdmin: isTotalAdmin)
            return
        }

        isLoadingBrandContent = true
        message = nil
        defer { isLoadingBrandContent = false }

        do {
            let fetchedSeasons = try await seasonRepository.fetchAllSeasons(brandID: brandID)
            seasons = fetchedSeasons.sorted(by: Season.defaultSort)
            selectedSeasonIDs = selectedSeasonIDs.filter { seasonID in
                seasons.contains { $0.id == seasonID }
            }
            if let expandedSeason,
               seasons.contains(where: { $0.id == expandedSeason.id }) == false {
                self.expandedSeason = nil
                resetPostPaging()
            }
            await reloadDeletionRequests(isTotalAdmin: isTotalAdmin)
        } catch {
            seasons = []
            resetSelectionState()
            setMessage("시즌 목록을 불러오지 못했습니다: \(error.localizedDescription)", autoDismiss: false)
        }
    }

    func toggleSeasonSelection(_ season: Season) {
        if selectedSeasonIDs.contains(season.id) {
            selectedSeasonIDs.remove(season.id)
        } else {
            selectedSeasonIDs.insert(season.id)
        }
    }

    func toggleExpandedSeason(_ season: Season) async {
        if expandedSeason?.id == season.id {
            expandedSeason = nil
            resetPostPaging()
            return
        }

        expandedSeason = season
        selectedPostIDs = []
        await reloadPosts(season: season)
    }

    func reloadPosts(season: Season) async {
        isLoadingPosts = true
        message = nil
        resetPostPaging()
        defer { isLoadingPosts = false }

        do {
            let page = try await postRepository.fetchPosts(
                brandID: season.brandID,
                seasonID: season.id,
                sort: .newest,
                filterTagIDs: [],
                page: PageRequest(size: postPageSize, cursor: nil)
            )
            posts = page.items
            nextPostCursor = page.nextCursor
        } catch {
            posts = []
            nextPostCursor = nil
            setMessage("포스트 목록을 불러오지 못했습니다: \(error.localizedDescription)", autoDismiss: false)
        }
    }

    func loadMorePostsIfNeeded(currentPostID: PostID) async {
        guard let expandedSeason,
              let nextPostCursor,
              isLoadingPosts == false,
              isLoadingMorePosts == false,
              shouldLoadMorePosts(currentPostID: currentPostID)
        else {
            return
        }

        isLoadingMorePosts = true
        defer { isLoadingMorePosts = false }

        do {
            let page = try await postRepository.fetchPosts(
                brandID: expandedSeason.brandID,
                seasonID: expandedSeason.id,
                sort: .newest,
                filterTagIDs: [],
                page: PageRequest(size: postPageSize, cursor: nextPostCursor)
            )
            posts.append(contentsOf: page.items)
            self.nextPostCursor = page.nextCursor
        } catch {
            setMessage("포스트 추가 목록을 불러오지 못했습니다: \(error.localizedDescription)", autoDismiss: false)
        }
    }

    func togglePostSelection(_ post: LookbookPost) {
        if selectedPostIDs.contains(post.id) {
            selectedPostIDs.remove(post.id)
        } else {
            selectedPostIDs.insert(post.id)
        }
    }

    func isSeasonSelected(_ season: Season) -> Bool {
        selectedSeasonIDs.contains(season.id)
    }

    func isPostSelected(_ post: LookbookPost) -> Bool {
        selectedPostIDs.contains(post.id)
    }

    func reloadDeletionRequests(isTotalAdmin: Bool) async {
        isLoadingRequests = true
        defer { isLoadingRequests = false }

        do {
            let page = try await deletionRepository.listDeletionRequests(
                status: .active,
                targetType: nil,
                brandID: deletionRequestBrandID(isTotalAdmin: isTotalAdmin),
                limit: 50,
                cursor: nil
            )
            if isTotalAdmin {
                deletionRequests = page.requests
            } else {
                deletionRequests = page.requests.filter { $0.targetType != .brand }
            }
        } catch {
            deletionRequests = []
            if selectedBrand != nil || isTotalAdmin {
                setMessage("삭제 요청 목록을 불러오지 못했습니다: \(error.localizedDescription)", autoDismiss: false)
            }
        }
    }

    func requestBrandDeletion(isTotalAdmin: Bool) async {
        guard isTotalAdmin, let brand = selectedBrand else { return }
        await performDeletionMutation(key: "brand:\(brand.id.value)") {
            _ = try await deletionRepository.requestBrandDeletion(
                brandID: brand.id,
                reason: normalizedReason
            )
            reasonText = ""
            setMessage("브랜드 삭제 요청을 등록했습니다.", autoDismiss: true)
            await clearSelectedBrand(isTotalAdmin: isTotalAdmin)
        }
    }

    func softDeleteSelectedSeasons(isTotalAdmin: Bool) async {
        guard let brandID = selectedBrand?.id, selectedSeasonIDs.isEmpty == false else { return }
        let seasonIDs = Array(selectedSeasonIDs)
        await performDeletionMutation(key: "batch:seasons") {
            let result = try await deletionRepository.batchSoftDeleteSeasons(
                brandID: brandID,
                seasonIDs: seasonIDs,
                reason: normalizedReason
            )
            applySeasonBatchResult(result)
            reasonText = ""
            setMessage(batchMessage(result: result, targetName: "시즌"), autoDismiss: true)
            await reloadBrandContent(isTotalAdmin: isTotalAdmin)
        }
    }

    func softDeleteSelectedPosts(isTotalAdmin: Bool) async {
        guard let brandID = selectedBrand?.id,
              let expandedSeason,
              selectedPostIDs.isEmpty == false
        else {
            return
        }

        let postIDs = Array(selectedPostIDs)
        await performDeletionMutation(key: "batch:posts") {
            let result = try await deletionRepository.batchSoftDeletePosts(
                brandID: brandID,
                seasonID: expandedSeason.id,
                postIDs: postIDs,
                reason: normalizedReason
            )
            applyPostBatchResult(result)
            reasonText = ""
            setMessage(batchMessage(result: result, targetName: "포스트"), autoDismiss: true)
            await reloadPosts(season: expandedSeason)
            await reloadDeletionRequests(isTotalAdmin: isTotalAdmin)
        }
    }

    func softDeleteSeason(_ season: Season, isTotalAdmin: Bool) async {
        selectedSeasonIDs = [season.id]
        await softDeleteSelectedSeasons(isTotalAdmin: isTotalAdmin)
    }

    func softDeletePost(_ post: LookbookPost, isTotalAdmin: Bool) async {
        selectedPostIDs = [post.id]
        await softDeleteSelectedPosts(isTotalAdmin: isTotalAdmin)
    }

    func cancelBrandDeletion(_ request: LookbookDeletionRequest, isTotalAdmin: Bool) async {
        guard isTotalAdmin, request.targetType == .brand else { return }
        await performDeletionMutation(key: "request:\(request.requestID)") {
            _ = try await deletionRepository.cancelBrandDeletion(brandID: request.brandID)
            setMessage("브랜드를 복구했습니다.", autoDismiss: true)
            await reloadDeletionRequests(isTotalAdmin: isTotalAdmin)
        }
    }

    func restore(_ request: LookbookDeletionRequest, isTotalAdmin: Bool) async {
        await performDeletionMutation(key: "request:\(request.requestID)") {
            switch request.targetType {
            case .brand:
                return
            case .season:
                guard let seasonID = request.seasonID else { return }
                _ = try await deletionRepository.restoreSeason(
                    brandID: request.brandID,
                    seasonID: seasonID
                )
                setMessage("시즌을 복구했습니다.", autoDismiss: true)
            case .post:
                guard let seasonID = request.seasonID,
                      let postID = request.postID else { return }
                _ = try await deletionRepository.restorePost(
                    brandID: request.brandID,
                    seasonID: seasonID,
                    postID: postID
                )
                setMessage("포스트를 복구했습니다.", autoDismiss: true)
            }
            await reloadBrandContent(isTotalAdmin: isTotalAdmin)
            if let expandedSeason {
                await reloadPosts(season: expandedSeason)
            }
        }
    }

    func scheduleMessageAutoDismissIfNeeded(_ message: String?) {
        messageDismissTask?.cancel()
        guard let message, autoDismissDelay(for: message) != nil else { return }
        scheduleMessageAutoDismiss(message, delay: autoDismissDelay(for: message) ?? FeedbackDismissDelay.result)
    }

    private func performDeletionMutation(
        key: String,
        operation: () async throws -> Void
    ) async {
        guard mutationKey == nil else { return }
        mutationKey = key
        message = nil
        messageDismissTask?.cancel()
        defer { mutationKey = nil }

        do {
            try await operation()
        } catch {
            setMessage("삭제 관리 작업 실패: \(error.localizedDescription)", autoDismiss: true)
        }
    }

    private func bindSearchText() {
        $searchText
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] query in
                self?.scheduleSearch(query: query)
            }
            .store(in: &cancellables)
    }

    private func scheduleSearch(query: String) {
        searchTask?.cancel()

        guard shouldShowBrandSearch, query.isEmpty == false else {
            searchResults = []
            isSearching = false
            return
        }

        searchTask = Task { [weak self] in
            await self?.searchBrands(query: query)
        }
    }

    private func searchBrands(query: String) async {
        isSearching = true
        defer { isSearching = false }

        do {
            let results = try await searchUseCase.execute(query: query, limit: 20)
            guard !Task.isCancelled else { return }
            searchResults = await verifiedVisibleBrands(results)
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            setMessage("브랜드 검색 실패: \(error.localizedDescription)", autoDismiss: false)
        }
    }

    private func verifiedVisibleBrands(_ brands: [Brand]) async -> [Brand] {
        var visibleBrands: [Brand] = []
        visibleBrands.reserveCapacity(brands.count)

        for brand in brands where brand.isVisibleToUsers {
            do {
                let fetched = try await brandRepository.fetchBrand(brandID: brand.id)
                visibleBrands.append(fetched)
            } catch {
                continue
            }
        }

        return visibleBrands
    }

    private func deletionRequestBrandID(isTotalAdmin: Bool) -> BrandID? {
        if isTotalAdmin, isBrandScoped == false {
            return nil
        }
        return selectedBrand?.id
    }

    private func resetSelectionState() {
        selectedSeasonIDs = []
        selectedPostIDs = []
        expandedSeason = nil
        resetPostPaging()
    }

    private func resetPostPaging() {
        posts = []
        nextPostCursor = nil
        selectedPostIDs = []
    }

    private func shouldLoadMorePosts(currentPostID: PostID) -> Bool {
        guard let index = posts.firstIndex(where: { $0.id == currentPostID }) else {
            return false
        }
        return index >= max(posts.count - 6, 0)
    }

    private func applySeasonBatchResult(_ result: LookbookDeletionBatchResult) {
        let succeededIDs = Set(result.results.compactMap { item -> SeasonID? in
            guard item.success else { return nil }
            return item.seasonID ?? SeasonID(value: item.targetID)
        })
        selectedSeasonIDs.subtract(succeededIDs)
        if let expandedSeason, succeededIDs.contains(expandedSeason.id) {
            self.expandedSeason = nil
            resetPostPaging()
        }
    }

    private func applyPostBatchResult(_ result: LookbookDeletionBatchResult) {
        let succeededIDs = Set(result.results.compactMap { item -> PostID? in
            guard item.success else { return nil }
            return item.postID ?? PostID(value: item.targetID)
        })
        selectedPostIDs.subtract(succeededIDs)
    }

    private func batchMessage(result: LookbookDeletionBatchResult, targetName: String) -> String {
        if result.failedCount == 0 {
            return "\(targetName) \(result.succeededCount)개 삭제 요청을 등록했습니다."
        }
        return "\(targetName) \(result.succeededCount)개 삭제 요청을 등록했고 \(result.failedCount)개는 실패했습니다."
    }

    private func setMessage(_ message: String, autoDismiss: Bool) {
        self.message = message
        messageDismissTask?.cancel()
        guard autoDismiss else { return }
        let delay = autoDismissDelay(for: message) ?? FeedbackDismissDelay.result
        scheduleMessageAutoDismiss(message, delay: delay)
    }

    private func scheduleMessageAutoDismiss(_ message: String, delay: UInt64) {
        messageDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.message == message else { return }
                self?.message = nil
            }
        }
    }

    private func autoDismissDelay(for message: String) -> UInt64? {
        if message.contains("실패") || message.contains("불러오지 못했습니다") {
            return FeedbackDismissDelay.failure
        }
        if message.contains("등록했습니다") || message.contains("복구했습니다") {
            return FeedbackDismissDelay.result
        }
        return nil
    }
}
