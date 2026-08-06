//
//  AdminBrandManagementViewModel.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation
import Combine
import UIKit

@MainActor
final class AdminBrandManagementViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published private(set) var searchResults: [Brand] = []
    @Published private(set) var selectedBrand: Brand?
    @Published var brandName: String = ""
    @Published var englishName: String = ""
    @Published var websiteURLText: String = ""
    @Published var lookbookArchiveURLText: String = ""
    @Published var isFeatured: Bool = false
    @Published private(set) var moods: [StyleMood] = []
    @Published var selectedMoodIDs: Set<String> = []
    @Published private(set) var seasons: [Season] = []
    @Published var seasonSearchText: String = ""
    @Published var managerEmail: String = ""
    @Published var managerRole: BrandManagerRole = .admin
    @Published private(set) var selectedLogoImage: UIImage?
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var isLoadingInitialBrand: Bool = false
    @Published private(set) var isSavingBrand: Bool = false
    @Published private(set) var isUploadingLogo: Bool = false
    @Published private(set) var isMutatingManager: Bool = false
    @Published private(set) var isLoadingMoodData: Bool = false
    @Published private(set) var isCreatingMood: Bool = false
    @Published private(set) var savingSeasonIDs: Set<SeasonID> = []
    @Published var message: String? {
        didSet {
            scheduleMessageAutoDismissIfNeeded(message)
        }
    }

    let isDirectBrandMode: Bool
    private let initialBrandID: BrandID?
    private let brandRepository: any BrandRepositoryProtocol
    private let searchUseCase: any SearchBrandsUseCaseProtocol
    private let brandStore: BrandStoringRepository
    private let storageService: StorageServiceProtocol
    private let brandImageCache: any BrandImageCacheProtocol
    private let thumbnailer: ImageThumbnailing
    private let moodRepository: StyleMoodRepositoryProtocol
    private let moodAdminRepository: StyleMoodAdminRepositoryProtocol
    private let seasonRepository: SeasonRepositoryProtocol
    private let seasonMoodAdminRepository: SeasonMoodAdminRepositoryProtocol
    private let onBrandUpdated: ((Brand) -> Void)?
    private var selectedLogoThumbData: Data?
    private var selectedLogoDetailData: Data?
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private var messageDismissTask: Task<Void, Never>?
    private var didLoadInitialBrand = false

    private enum FeedbackDismissDelay {
        static let result: UInt64 = 2_500_000_000
        static let failure: UInt64 = 4_000_000_000
    }

    init(
        initialBrand: Brand? = nil,
        initialBrandID: BrandID? = nil,
        brandRepository: any BrandRepositoryProtocol,
        searchUseCase: any SearchBrandsUseCaseProtocol,
        brandStore: BrandStoringRepository,
        storageService: StorageServiceProtocol,
        brandImageCache: any BrandImageCacheProtocol,
        thumbnailer: ImageThumbnailing,
        moodRepository: StyleMoodRepositoryProtocol =
            FirestoreStyleMoodRepository(db: .firestore()),
        moodAdminRepository: StyleMoodAdminRepositoryProtocol =
            CloudFunctionsStyleMoodAdminRepository(),
        seasonRepository: SeasonRepositoryProtocol = FirestoreSeasonRepository(),
        seasonMoodAdminRepository: SeasonMoodAdminRepositoryProtocol =
            CloudFunctionsSeasonMoodAdminRepository(),
        onBrandUpdated: ((Brand) -> Void)? = nil
    ) {
        self.initialBrandID = initialBrandID ?? initialBrand?.id
        self.isDirectBrandMode = initialBrandID != nil || initialBrand != nil
        self.brandRepository = brandRepository
        self.searchUseCase = searchUseCase
        self.brandStore = brandStore
        self.storageService = storageService
        self.brandImageCache = brandImageCache
        self.thumbnailer = thumbnailer
        self.moodRepository = moodRepository
        self.moodAdminRepository = moodAdminRepository
        self.seasonRepository = seasonRepository
        self.seasonMoodAdminRepository = seasonMoodAdminRepository
        self.onBrandUpdated = onBrandUpdated
        bindSearchText()

        if let initialBrand {
            didLoadInitialBrand = true
            selectBrand(initialBrand)
        } else {
            self.isLoadingInitialBrand = initialBrandID != nil
        }
    }

    var canSaveBrand: Bool {
        canSaveBrand(canUpdateFeatured: true)
    }

    func canSaveBrand(
        canUpdateFeatured: Bool,
        canUpdateMoodIDs: Bool = false
    ) -> Bool {
        selectedBrand != nil &&
        brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        hasBrandInfoChanges(
            canUpdateFeatured: canUpdateFeatured,
            canUpdateMoodIDs: canUpdateMoodIDs
        ) &&
        isSavingBrand == false
    }

    var canUploadLogo: Bool {
        selectedBrand != nil &&
        selectedLogoThumbData != nil &&
        selectedLogoDetailData != nil &&
        isUploadingLogo == false
    }

    var canMutateManager: Bool {
        selectedBrand != nil &&
        managerEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        isMutatingManager == false
    }

    var visibleSeasons: [Season] {
        let query = normalizedSearchTerm(seasonSearchText)
        guard query.isEmpty == false else { return seasons }

        return seasons.filter { season in
            let searchTerms = [
                season.displayTitle,
                season.sourceTitle,
                season.year.map { String($0) },
                season.term?.rawValue,
                season.term?.displayText
            ]
            .compactMap { $0 }

            return searchTerms.contains {
                normalizedSearchTerm($0).contains(query)
            }
        }
    }

    func clearSearch() {
        searchText = ""
        clearSelectedBrand()
    }

    func loadInitialBrandIfNeeded() async {
        guard let initialBrandID else { return }
        guard didLoadInitialBrand == false else { return }

        didLoadInitialBrand = true
        isLoadingInitialBrand = true
        message = nil
        defer { isLoadingInitialBrand = false }

        do {
            let brand = try await brandRepository.fetchBrand(brandID: initialBrandID)
            selectBrand(brand)
        } catch {
            message = "관리할 브랜드 정보를 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func searchBrands(query: String) async {
        guard query.isEmpty == false else {
            searchResults = []
            return
        }

        isSearching = true
        message = nil
        defer { isSearching = false }

        do {
            let results = try await searchUseCase.execute(query: query, limit: 20)
            guard !Task.isCancelled else { return }
            searchResults = await verifiedVisibleBrands(results)
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            message = "브랜드 검색 실패: \(error.localizedDescription)"
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

    func selectBrand(_ brand: Brand) {
        selectedBrand = brand
        brandName = brand.name
        englishName = brand.englishName ?? ""
        websiteURLText = brand.websiteURL ?? ""
        lookbookArchiveURLText = brand.lookbookArchiveURL ?? ""
        isFeatured = brand.isFeatured
        selectedMoodIDs = Set(brand.moodIDs)
        seasons = []
        seasonSearchText = ""
        selectedLogoImage = nil
        selectedLogoThumbData = nil
        selectedLogoDetailData = nil
        message = nil
    }

    func hasBrandInfoChanges(
        canUpdateFeatured: Bool,
        canUpdateMoodIDs: Bool = false
    ) -> Bool {
        guard let selectedBrand else { return false }

        let normalizedName = normalizedDisplayName(brandName)
        let normalizedEnglishName = normalizedOptionalDisplayName(englishName)
        if normalizedName != selectedBrand.name { return true }
        if normalizedEnglishName != selectedBrand.englishName { return true }
        if urlInputDiffers(websiteURLText, from: selectedBrand.websiteURL) { return true }
        if urlInputDiffers(lookbookArchiveURLText, from: selectedBrand.lookbookArchiveURL) { return true }
        if canUpdateFeatured, isFeatured != selectedBrand.isFeatured { return true }
        if canUpdateMoodIDs, selectedMoodIDs != Set(selectedBrand.moodIDs) { return true }

        return false
    }

    func setPickedLogo(image: UIImage, data: Data) {
        do {
            let thumbData = try thumbnailer.makeThumbnailJPEGData(
                from: data,
                policy: ThumbnailPolicies.brandLogoList
            )
            let detailData = try thumbnailer.makeThumbnailJPEGData(
                from: data,
                policy: ThumbnailPolicies.brandLogoDetail
            )
            selectedLogoImage = image
            selectedLogoThumbData = thumbData
            selectedLogoDetailData = detailData
            message = nil
        } catch {
            message = "로고 이미지 처리 실패: \(error.localizedDescription)"
        }
    }

    func clearPickedLogo() {
        selectedLogoImage = nil
        selectedLogoThumbData = nil
        selectedLogoDetailData = nil
    }

    func saveBrand(
        canUpdateFeatured: Bool,
        canUpdateMoodIDs: Bool = false
    ) async {
        guard let selectedBrand else { return }
        message = nil

        let name = normalizedDisplayName(brandName)
        guard name.isEmpty == false else {
            message = "브랜드명을 입력해주세요."
            return
        }
        let normalizedEnglishName = normalizedDisplayName(englishName)

        let websiteURL: String?
        let lookbookArchiveURL: String?
        do {
            websiteURL = try normalizedHTTPURL(websiteURLText, fieldLabel: "공식 홈페이지 URL")
            lookbookArchiveURL = try normalizedHTTPURL(lookbookArchiveURLText, fieldLabel: "룩북 목록 URL")
        } catch {
            message = error.localizedDescription
            return
        }

        isSavingBrand = true
        defer { isSavingBrand = false }

        do {
            let moodIDsPatch = canUpdateMoodIDs &&
                selectedMoodIDs != Set(selectedBrand.moodIDs)
                ? orderedMoodIDs(selectedMoodIDs)
                : nil
            let updatedBrand = try await brandStore.updateBrand(
                brandID: selectedBrand.id,
                name: name,
                englishName: normalizedEnglishName.isEmpty ? nil : normalizedEnglishName,
                websiteURL: websiteURL,
                lookbookArchiveURL: lookbookArchiveURL,
                isFeatured: canUpdateFeatured ? isFeatured : nil,
                moodIDs: moodIDsPatch
            )
            self.selectedBrand = updatedBrand
            self.brandName = updatedBrand.name
            self.englishName = updatedBrand.englishName ?? ""
            self.websiteURLText = updatedBrand.websiteURL ?? ""
            self.lookbookArchiveURLText = updatedBrand.lookbookArchiveURL ?? ""
            self.isFeatured = updatedBrand.isFeatured
            self.selectedMoodIDs = Set(updatedBrand.moodIDs)
            onBrandUpdated?(updatedBrand)
            message = "브랜드 정보를 저장했습니다."
        } catch {
            message = "브랜드 저장 실패: \(error.localizedDescription)"
        }
    }

    func uploadLogo() async {
        guard let selectedBrand,
              let selectedLogoThumbData,
              let selectedLogoDetailData
        else { return }

        isUploadingLogo = true
        message = nil
        defer { isUploadingLogo = false }

        let thumbPath = "brands/\(selectedBrand.id.value)/logo/thumb.jpg"
        let detailPath = "brands/\(selectedBrand.id.value)/logo/detail.jpg"

        do {
            let uploadedThumbPath = try await storageService.uploadImage(
                data: selectedLogoThumbData,
                to: thumbPath
            )
            let uploadedDetailPath = try await storageService.uploadImage(
                data: selectedLogoDetailData,
                to: detailPath
            )
            try await brandStore.updateLogoPaths(
                docID: selectedBrand.id.value,
                logoThumbPath: uploadedThumbPath,
                logoDetailPath: uploadedDetailPath
            )
            try? await brandImageCache.storeImageData(
                selectedLogoThumbData,
                path: uploadedThumbPath
            )
            try? await brandImageCache.storeImageData(
                selectedLogoDetailData,
                path: uploadedDetailPath
            )

            let updatedBrand = Brand(
                id: selectedBrand.id,
                name: selectedBrand.name,
                englishName: selectedBrand.englishName,
                websiteURL: selectedBrand.websiteURL,
                lookbookArchiveURL: selectedBrand.lookbookArchiveURL,
                logoThumbPath: uploadedThumbPath,
                logoDetailPath: uploadedDetailPath,
                logoOriginalPath: selectedBrand.logoOriginalPath,
                isFeatured: selectedBrand.isFeatured,
                moodIDs: selectedBrand.moodIDs,
                discoveryStatus: selectedBrand.discoveryStatus,
                lastDiscoveryErrorMessage: selectedBrand.lastDiscoveryErrorMessage,
                lastDiscoveryRequestedAt: selectedBrand.lastDiscoveryRequestedAt,
                lastDiscoveryCompletedAt: selectedBrand.lastDiscoveryCompletedAt,
                metrics: selectedBrand.metrics,
                deletionStatus: selectedBrand.deletionStatus,
                updatedAt: Date()
            )
            self.selectedBrand = updatedBrand
            clearPickedLogo()
            onBrandUpdated?(updatedBrand)
            message = "로고를 저장했습니다."
        } catch {
            message = "로고 저장에 실패했습니다. 다시 시도해주세요."
        }
    }

    func addManager() async {
        await mutateManager(isAdding: true)
    }

    func removeManager() async {
        await mutateManager(isAdding: false)
    }

    func loadMoodManagementData() async {
        guard let selectedBrand else { return }
        isLoadingMoodData = true
        message = nil
        defer { isLoadingMoodData = false }

        do {
            async let loadedMoods = moodRepository.fetchAllMoods()
            async let loadedSeasons = seasonRepository.fetchAllSeasons(brandID: selectedBrand.id)
            let (moods, seasons) = try await (loadedMoods, loadedSeasons)
            guard self.selectedBrand?.id == selectedBrand.id else { return }
            self.moods = moods
            self.seasons = seasons
        } catch {
            message = "브랜드·시즌 스타일 정보를 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    func createMood(_ draft: StyleMoodMutationDraft) async -> Bool {
        guard isCreatingMood == false else { return false }
        guard selectedMoodIDs.count < 5 else {
            message = "브랜드 스타일은 최대 5개까지 선택할 수 있습니다"
            return false
        }
        isCreatingMood = true
        defer { isCreatingMood = false }
        do {
            let moodID = try await moodAdminRepository.createMood(draft)
            moods = try await moodRepository.fetchAllMoods()
            selectedMoodIDs.insert(moodID)
            return true
        } catch {
            message = "스타일 키워드를 추가하지 못했습니다: \(error.localizedDescription)"
            return false
        }
    }

    func updateSeasonMoods(
        seasonID: SeasonID,
        selectedMoodIDs: Set<String>
    ) async -> Bool {
        guard let brandID = selectedBrand?.id else { return false }
        guard savingSeasonIDs.contains(seasonID) == false else { return false }
        savingSeasonIDs.insert(seasonID)
        defer { savingSeasonIDs.remove(seasonID) }

        do {
            let moodIDs = orderedMoodIDs(selectedMoodIDs)
            try await seasonMoodAdminRepository.updateSeasonMoods(
                brandID: brandID,
                seasonID: seasonID,
                moodIDs: moodIDs
            )
            if let index = seasons.firstIndex(where: { $0.id == seasonID }) {
                seasons[index].moodIDs = moodIDs
            }
            message = "시즌 스타일을 저장했습니다."
            return true
        } catch {
            message = "시즌 스타일을 저장하지 못했습니다: \(error.localizedDescription)"
            return false
        }
    }

    private func mutateManager(isAdding: Bool) async {
        guard let selectedBrand else { return }
        let email = managerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.isEmpty == false else {
            message = "관리자 이메일을 입력해주세요."
            return
        }

        isMutatingManager = true
        message = nil
        defer { isMutatingManager = false }

        do {
            let receipt: BrandManagerMutationReceipt
            if isAdding {
                receipt = try await brandStore.addBrandManager(
                    brandID: selectedBrand.id,
                    email: email,
                    role: managerRole
                )
            } else {
                receipt = try await brandStore.removeBrandManager(
                    brandID: selectedBrand.id,
                    email: email,
                    role: managerRole
                )
            }

            if isAdding {
                message = receipt.duplicate ? "이미 등록된 관리자입니다." : "관리자를 추가했습니다."
                if receipt.duplicate == false {
                    managerEmail = ""
                }
            } else {
                message = receipt.removed ? "관리자를 삭제했습니다." : "대상 관리자가 등록되어 있지 않습니다."
            }
        } catch {
            message = "관리자 변경 실패: \(error.localizedDescription)"
        }
    }
}

private extension AdminBrandManagementViewModel {
    func orderedMoodIDs(_ selectedIDs: Set<String>) -> [String] {
        moods
            .filter { selectedIDs.contains($0.id) }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.id < $1.id
            }
            .map(\.id)
    }

    func bindSearchText() {
        $searchText
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] query in
                self?.scheduleSearch(query: query)
            }
            .store(in: &cancellables)
    }

    func scheduleSearch(query: String) {
        searchTask?.cancel()

        guard query.isEmpty == false else {
            searchResults = []
            isSearching = false
            if isDirectBrandMode == false {
                clearSelectedBrand()
            }
            return
        }

        searchTask = Task { [weak self] in
            await self?.searchBrands(query: query)
        }
    }

    func normalizedDisplayName(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    func normalizedSearchTerm(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    func normalizedOptionalDisplayName(_ rawValue: String) -> String? {
        let value = normalizedDisplayName(rawValue)
        return value.isEmpty ? nil : value
    }

    func normalizedHTTPURL(_ rawValue: String, fieldLabel: String) throws -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate) else {
            throw NSError(
                domain: "AdminBrandManagementViewModel",
                code: -20,
                userInfo: [NSLocalizedDescriptionKey: "\(fieldLabel) 형식이 올바르지 않습니다."]
            )
        }

        guard let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw NSError(
                domain: "AdminBrandManagementViewModel",
                code: -21,
                userInfo: [NSLocalizedDescriptionKey: "\(fieldLabel)은 http 또는 https로 시작해야 합니다."]
            )
        }

        guard let host = components.host, host.isEmpty == false else {
            throw NSError(
                domain: "AdminBrandManagementViewModel",
                code: -22,
                userInfo: [NSLocalizedDescriptionKey: "\(fieldLabel)에 도메인이 필요합니다."]
            )
        }

        components.scheme = scheme
        components.host = host.lowercased()

        guard let normalized = components.string else {
            throw NSError(
                domain: "AdminBrandManagementViewModel",
                code: -23,
                userInfo: [NSLocalizedDescriptionKey: "\(fieldLabel)을 정규화하지 못했습니다."]
            )
        }

        return normalized
    }

    func urlInputDiffers(_ rawValue: String, from savedValue: String?) -> Bool {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return savedValue != nil
        }

        guard let normalized = try? normalizedHTTPURL(trimmed, fieldLabel: "") else {
            return true
        }

        return normalized != savedValue
    }

    func scheduleMessageAutoDismissIfNeeded(_ message: String?) {
        messageDismissTask?.cancel()
        guard let message, let delay = autoDismissDelay(for: message) else { return }

        messageDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.message == message else { return }
                self?.message = nil
            }
        }
    }

    func autoDismissDelay(for message: String) -> UInt64? {
        let resultMessages = [
            "브랜드 정보를 저장했습니다.",
            "로고를 저장했습니다.",
            "관리자를 추가했습니다.",
            "관리자를 삭제했습니다.",
            "이미 등록된 관리자입니다.",
            "대상 관리자가 등록되어 있지 않습니다."
        ]

        if resultMessages.contains(message) {
            return FeedbackDismissDelay.result
        }

        if message.hasPrefix("브랜드 저장 실패:") ||
            message == "로고 저장에 실패했습니다. 다시 시도해주세요." ||
            message.hasPrefix("관리자 변경 실패:") {
            return FeedbackDismissDelay.failure
        }

        return nil
    }

    func clearSelectedBrand() {
        selectedBrand = nil
        brandName = ""
        englishName = ""
        websiteURLText = ""
        lookbookArchiveURLText = ""
        isFeatured = false
        selectedMoodIDs = []
        seasons = []
        seasonSearchText = ""
        managerEmail = ""
        managerRole = .admin
        selectedLogoImage = nil
        selectedLogoThumbData = nil
        selectedLogoDetailData = nil
    }
}
