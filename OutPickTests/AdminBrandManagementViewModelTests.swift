//
//  AdminBrandManagementViewModelTests.swift
//  OutPickTests
//
//  Created by Codex on 7/7/26.
//

import Foundation
import FirebaseFirestore
import FirebaseStorage
import Testing
import UIKit
@testable import OutPick

@MainActor
struct AdminBrandManagementViewModelTests {
    @Test func canSaveBrandRequiresActualBrandInfoChange() {
        let viewModel = makeViewModel()
        let brand = makeBrand(
            name: "Hatchingroom",
            englishName: "Hatchingroom",
            websiteURL: "https://hatchingroom.com",
            lookbookArchiveURL: "https://hatchingroom.com/archive",
            isFeatured: false
        )
        viewModel.selectBrand(brand)

        #expect(viewModel.canSaveBrand(canUpdateFeatured: true) == false)

        viewModel.brandName = "  Hatchingroom  "
        viewModel.websiteURLText = "hatchingroom.com"
        #expect(viewModel.canSaveBrand(canUpdateFeatured: true) == false)

        viewModel.lookbookArchiveURLText = "https://hatchingroom.com/new-archive"
        #expect(viewModel.canSaveBrand(canUpdateFeatured: true) == true)
    }

    @Test func featuredChangeOnlyCountsForTotalAdminSavePermission() {
        let viewModel = makeViewModel()
        viewModel.selectBrand(makeBrand(isFeatured: false))

        viewModel.isFeatured = true

        #expect(viewModel.canSaveBrand(canUpdateFeatured: false) == false)
        #expect(viewModel.canSaveBrand(canUpdateFeatured: true) == true)
    }

    @Test func moodChangeOnlyCountsForTotalAdminSavePermission() {
        let viewModel = makeViewModel()
        viewModel.selectBrand(makeBrand(moodIDs: ["minimal"]))

        viewModel.selectedMoodIDs = ["street"]

        #expect(
            viewModel.canSaveBrand(
                canUpdateFeatured: false,
                canUpdateMoodIDs: false
            ) == false
        )
        #expect(
            viewModel.canSaveBrand(
                canUpdateFeatured: false,
                canUpdateMoodIDs: true
            )
        )
    }

    @Test func clearSearchClearsSelectedBrandAndDraftInputs() {
        let viewModel = makeViewModel()
        viewModel.searchText = "hat"
        viewModel.selectBrand(makeBrand())
        viewModel.managerEmail = "manager@example.com"

        viewModel.clearSearch()

        #expect(viewModel.searchText == "")
        #expect(viewModel.selectedBrand == nil)
        #expect(viewModel.brandName == "")
        #expect(viewModel.managerEmail == "")
    }

    @Test func directBrandModeWithInitialBrandStartsReadyWithoutFetchLoading() {
        let brand = makeBrand(name: "Ready Brand")
        let viewModel = makeViewModel(initialBrand: brand)

        #expect(viewModel.isDirectBrandMode == true)
        #expect(viewModel.isLoadingInitialBrand == false)
        #expect(viewModel.selectedBrand == brand)
        #expect(viewModel.brandName == "Ready Brand")
    }

    @Test func directBrandModeKeepsInitialBrandAfterSearchBindingEmitsEmptyQuery() async {
        let brand = makeBrand(name: "Ready Brand")
        let viewModel = makeViewModel(initialBrand: brand)

        try? await Task.sleep(nanoseconds: 500_000_000)

        #expect(viewModel.selectedBrand == brand)
        #expect(viewModel.brandName == "Ready Brand")
    }

    @Test func directBrandModeWithOnlyBrandIDStartsInInitialLoadingState() {
        let viewModel = makeViewModel(initialBrandID: BrandID(value: "brand-1"))

        #expect(viewModel.isDirectBrandMode == true)
        #expect(viewModel.isLoadingInitialBrand == true)
        #expect(viewModel.selectedBrand == nil)
    }

    @Test func seasonStyleSearchMatchesDisplaySourceYearAndTerm() async {
        let seasons = [
            makeSeason(
                id: "fw-2025",
                displayTitle: "25 F/W",
                sourceTitle: "Autumn Winter Collection",
                year: 2025,
                term: .fw
            ),
            makeSeason(
                id: "ss-2024",
                displayTitle: "24 S/S",
                sourceTitle: "Spring Summer Archive",
                year: 2024,
                term: .ss
            )
        ]
        let viewModel = makeViewModel(
            initialBrand: makeBrand(),
            seasonRepository: SeasonRepositoryStub(seasons: seasons)
        )
        await viewModel.loadMoodManagementData()

        viewModel.seasonSearchText = "winter"
        #expect(viewModel.visibleSeasons.map(\.id.value) == ["fw-2025"])

        viewModel.seasonSearchText = "2024"
        #expect(viewModel.visibleSeasons.map(\.id.value) == ["ss-2024"])

        viewModel.seasonSearchText = "SS"
        #expect(viewModel.visibleSeasons.map(\.id.value) == ["ss-2024"])

        viewModel.seasonSearchText = "F/W"
        #expect(viewModel.visibleSeasons.map(\.id.value) == ["fw-2025"])

        viewModel.seasonSearchText = "없는 시즌"
        #expect(viewModel.visibleSeasons.isEmpty)
    }

    @Test func logoUploadFailureHidesInternalError() async {
        let viewModel = makeViewModel(
            initialBrand: makeBrand(),
            storageService: StorageServiceStub(
                uploadError: AdminBrandManagementTestError.uploadFailed
            )
        )
        viewModel.setPickedLogo(
            image: UIImage(),
            data: Data([0xff, 0xd8, 0xff, 0xd9])
        )

        await viewModel.uploadLogo()

        #expect(
            viewModel.message ==
                "로고 저장에 실패했습니다. 다시 시도해주세요."
        )
        #expect(viewModel.message?.contains("내부 업로드 오류") == false)
    }

    private func makeViewModel(
        initialBrand: Brand? = nil,
        initialBrandID: BrandID? = nil,
        seasonRepository: SeasonRepositoryProtocol = SeasonRepositoryStub(),
        storageService: StorageServiceProtocol = StorageServiceStub()
    ) -> AdminBrandManagementViewModel {
        AdminBrandManagementViewModel(
            initialBrand: initialBrand,
            initialBrandID: initialBrandID,
            brandRepository: BrandRepositoryStub(),
            searchUseCase: SearchBrandsUseCaseStub(),
            brandStore: BrandStoringRepositoryStub(),
            storageService: storageService,
            brandImageCache: BrandImageCacheStub(),
            thumbnailer: ImageThumbnailerStub(),
            moodRepository: AdminStyleMoodRepositoryStub(),
            seasonRepository: seasonRepository
        )
    }

    private func makeBrand(
        name: String = "Brand",
        englishName: String? = nil,
        websiteURL: String? = nil,
        lookbookArchiveURL: String? = nil,
        isFeatured: Bool = false,
        moodIDs: [String] = []
    ) -> Brand {
        Brand(
            id: BrandID(value: "brand-1"),
            name: name,
            englishName: englishName,
            websiteURL: websiteURL,
            lookbookArchiveURL: lookbookArchiveURL,
            logoThumbPath: nil,
            logoDetailPath: nil,
            logoOriginalPath: nil,
            isFeatured: isFeatured,
            moodIDs: moodIDs,
            discoveryStatus: .idle,
            lastDiscoveryErrorMessage: nil,
            lastDiscoveryRequestedAt: nil,
            lastDiscoveryCompletedAt: nil,
            metrics: BrandMetrics(likeCount: 0, viewCount: 0, popularScore: 0),
            deletionStatus: .active,
            updatedAt: Date()
        )
    }

    private func makeSeason(
        id: String,
        displayTitle: String,
        sourceTitle: String?,
        year: Int?,
        term: SeasonTerm?
    ) -> Season {
        Season(
            id: SeasonID(value: id),
            brandID: BrandID(value: "brand-1"),
            displayTitle: displayTitle,
            sourceTitle: sourceTitle,
            year: year,
            term: term,
            coverPath: nil,
            coverRemoteURL: nil,
            description: "",
            tagIDs: [],
            moodIDs: [],
            status: .published,
            deletionStatus: .active,
            assetSyncStatus: .ready,
            metadataStatus: .confirmed,
            metadataConfidence: nil,
            sourceURL: nil,
            sourceImportJobID: nil,
            sourceSortIndex: nil,
            postCount: 0,
            likeCount: 0,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

private struct AdminStyleMoodRepositoryStub: StyleMoodRepositoryProtocol {
    func fetchOnboardingMoods() async throws -> [StyleMood] { [] }
    func fetchAllMoods() async throws -> [StyleMood] { [] }
}

private struct SeasonRepositoryStub: SeasonRepositoryProtocol {
    let seasons: [Season]

    init(seasons: [Season] = []) {
        self.seasons = seasons
    }

    func fetchSeason(brandID: BrandID, seasonID: SeasonID) async throws -> Season {
        guard let season = seasons.first(where: { $0.id == seasonID }) else {
            throw NSError(domain: "SeasonRepositoryStub", code: -1)
        }
        return season
    }

    func fetchSeasons(
        brandID: BrandID,
        pageSize: Int,
        after last: DocumentSnapshot?
    ) async throws -> SeasonPage {
        throw NSError(domain: "SeasonRepositoryStub", code: -1)
    }

    func fetchAllSeasons(brandID: BrandID) async throws -> [Season] {
        seasons
    }
}

private struct BrandRepositoryStub: BrandRepositoryProtocol {
    func fetchBrand(brandID: BrandID) async throws -> Brand {
        throw NSError(domain: "BrandRepositoryStub", code: -1)
    }

    func fetchBrands(
        sort: BrandSort?,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> BrandPage {
        throw NSError(domain: "BrandRepositoryStub", code: -1)
    }

    func fetchFeaturedBrands(
        sort: BrandSort?,
        limit: Int,
        after last: DocumentSnapshot?
    ) async throws -> BrandPage {
        throw NSError(domain: "BrandRepositoryStub", code: -1)
    }

    func fetchInterestedStyleBrands(
        moodIDs: [String],
        limit: Int,
        after cursor: InterestedStyleBrandCursor?
    ) async throws -> InterestedStyleBrandPage {
        throw NSError(domain: "BrandRepositoryStub", code: -1)
    }
}

private struct SearchBrandsUseCaseStub: SearchBrandsUseCaseProtocol {
    func execute(query: String, limit: Int) async throws -> [Brand] {
        []
    }
}

private struct BrandStoringRepositoryStub: BrandStoringRepository {
    func createBrand(
        name: String,
        englishName: String?,
        isFeatured: Bool,
        websiteURL: String?,
        lookbookArchiveURL: String?,
        moodIDs: [String]
    ) async throws -> BrandCreationReceipt {
        BrandCreationReceipt(brandID: "brand-1", discoveryJobID: nil)
    }

    func updateBrand(
        brandID: BrandID,
        name: String,
        englishName: String?,
        websiteURL: String?,
        lookbookArchiveURL: String?,
        isFeatured: Bool?,
        moodIDs: [String]?
    ) async throws -> Brand {
        Brand(
            id: brandID,
            name: name,
            englishName: englishName,
            websiteURL: websiteURL,
            lookbookArchiveURL: lookbookArchiveURL,
            logoThumbPath: nil,
            logoDetailPath: nil,
            logoOriginalPath: nil,
            isFeatured: isFeatured ?? false,
            moodIDs: moodIDs ?? [],
            discoveryStatus: .idle,
            lastDiscoveryErrorMessage: nil,
            lastDiscoveryRequestedAt: nil,
            lastDiscoveryCompletedAt: nil,
            metrics: BrandMetrics(likeCount: 0, viewCount: 0, popularScore: 0),
            deletionStatus: .active,
            updatedAt: Date()
        )
    }

    func updateLogoPaths(
        docID: String,
        logoThumbPath: String?,
        logoDetailPath: String?
    ) async throws {}

    func addBrandManager(
        brandID: BrandID,
        email: String,
        role: BrandManagerRole
    ) async throws -> BrandManagerMutationReceipt {
        BrandManagerMutationReceipt(
            brandID: brandID,
            userID: UserID(value: "user-1"),
            email: email,
            role: role,
            duplicate: false,
            removed: false
        )
    }

    func removeBrandManager(
        brandID: BrandID,
        email: String,
        role: BrandManagerRole
    ) async throws -> BrandManagerMutationReceipt {
        BrandManagerMutationReceipt(
            brandID: brandID,
            userID: UserID(value: "user-1"),
            email: email,
            role: role,
            duplicate: false,
            removed: true
        )
    }
}

private struct StorageServiceStub: StorageServiceProtocol {
    let uploadError: Error?

    init(uploadError: Error? = nil) {
        self.uploadError = uploadError
    }

    func uploadImage(data: Data, to path: String) async throws -> String {
        if let uploadError { throw uploadError }
        return path
    }
    func uploadImageFileWithRetryAndDataFallback(
        from fileURL: URL,
        to path: String,
        contentType: String
    ) async throws -> String { path }
    func uploadVideo(fileURL: URL, to path: String) async throws -> String { path }
    func uploadImages(_ datas: [Data], to folderPath: String) async throws -> [String] { [] }
    func downloadData(from path: String, maxSize: Int) async throws -> Data { Data() }
    func downloadFile(from path: String, to localURL: URL) async throws {}
    func downloadImage(from path: String, maxSize: Int) async throws -> Data { Data() }
    func downloadImages(_ paths: [String], maxSize: Int) async throws -> [Data] { [] }
    func deleteFile(at path: String) async throws {}
    func updateFile(data: Data, at path: String) async throws -> String { path }
    func updateMetadata(
        for path: String,
        metadata: StorageMetadata
    ) async throws -> StorageMetadata { metadata }
}

private enum AdminBrandManagementTestError: LocalizedError {
    case uploadFailed

    var errorDescription: String? {
        "내부 업로드 오류"
    }
}

private struct BrandImageCacheStub: BrandImageCacheProtocol {
    func loadImage(path: String, maxBytes: Int) async throws -> UIImage {
        UIImage()
    }

    func storeImageData(_ data: Data, path: String) async throws {}

    func removeImage(path: String) async {}

    func prefetch(
        items: [(path: String, maxBytes: Int)],
        concurrency: Int,
        storePolicy: ImageCacheStorePolicy
    ) async {}
}

private struct ImageThumbnailerStub: ImageThumbnailing {
    func makeThumbnailJPEGData(
        from originalJPEGData: Data,
        policy: ThumbnailPolicy
    ) throws -> Data {
        originalJPEGData
    }
}
