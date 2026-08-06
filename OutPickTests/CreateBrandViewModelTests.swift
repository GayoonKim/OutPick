import Foundation
import FirebaseStorage
import Testing
import UIKit
@testable import OutPick

@MainActor
struct CreateBrandViewModelTests {
    @Test func waitsForBothLogoUploadsAndPathPatchBeforeCompleting() async {
        let brandStore = CreateBrandStoreSpy()
        let storage = CreateBrandStorageSpy()
        let viewModel = makeViewModel(brandStore: brandStore, storage: storage)
        selectLogo(in: viewModel)

        let result = await viewModel.saveBrand()

        #expect(result?.hasLogoAsset == true)
        #expect(result?.discoveryJobID == "discovery-1")
        #expect(viewModel.createdBrandDocument?.hasLogoAsset == true)
        #expect(viewModel.message == nil)
        #expect(await brandStore.createCallCount == 1)
        #expect(await brandStore.logoPathPatches == [
            .init(
                brandID: "brand-1",
                thumbPath: "brands/brand-1/logo/thumb.jpg",
                detailPath: "brands/brand-1/logo/detail.jpg"
            )
        ])
        #expect(await storage.uploadedPaths == [
            "brands/brand-1/logo/thumb.jpg",
            "brands/brand-1/logo/detail.jpg"
        ])
    }

    @Test func logoFailureKeepsCreatedDocumentAndRetryDoesNotCreateDuplicate() async {
        let brandStore = CreateBrandStoreSpy()
        let storage = CreateBrandStorageSpy(failingUploadAttempts: 1)
        let viewModel = makeViewModel(brandStore: brandStore, storage: storage)
        selectLogo(in: viewModel)

        let firstResult = await viewModel.saveBrand()

        #expect(firstResult == nil)
        #expect(viewModel.createdBrandDocument?.id.value == "brand-1")
        #expect(viewModel.createdBrandDocument?.hasLogoAsset == false)
        #expect(
            viewModel.message ==
                "로고 저장에 실패했습니다. 다시 시도해주세요."
        )
        #expect(viewModel.message?.contains("테스트 업로드 실패") == false)
        #expect(await brandStore.createCallCount == 1)

        let retryResult = await viewModel.saveBrand()

        #expect(retryResult?.hasLogoAsset == true)
        #expect(await brandStore.createCallCount == 1)
        #expect(await brandStore.logoPathPatches.count == 1)
    }

    @Test func detailUploadFailureRollsBackUploadedThumbnail() async {
        let brandStore = CreateBrandStoreSpy()
        let storage = CreateBrandStorageSpy(
            failingPaths: ["brands/brand-1/logo/detail.jpg"]
        )
        let viewModel = makeViewModel(brandStore: brandStore, storage: storage)
        selectLogo(in: viewModel)

        let result = await viewModel.saveBrand()

        #expect(result == nil)
        #expect(await storage.deletedPaths == [
            "brands/brand-1/logo/thumb.jpg"
        ])
        #expect(await brandStore.logoPathPatches.isEmpty)
    }

    private func makeViewModel(
        brandStore: CreateBrandStoreSpy,
        storage: CreateBrandStorageSpy
    ) -> CreateBrandViewModel {
        let viewModel = CreateBrandViewModel(
            brandStore: brandStore,
            storageService: storage,
            thumbnailer: CreateBrandThumbnailerStub(),
            moodRepository: CreateBrandMoodRepositoryStub(),
            moodAdminRepository: CreateBrandMoodAdminRepositoryStub()
        )
        viewModel.brandName = "Test Brand"
        return viewModel
    }

    private func selectLogo(in viewModel: CreateBrandViewModel) {
        viewModel.setPickedLogo(
            thumbImage: UIImage(),
            thumbData: Data([0xff, 0xd8, 0xff, 0xd9]),
            detailData: Data([0xff, 0xd8, 0xff, 0xd9, 0x00])
        )
    }
}

private actor CreateBrandStoreSpy: BrandStoringRepository {
    struct LogoPathPatch: Equatable {
        let brandID: String
        let thumbPath: String?
        let detailPath: String?
    }

    private(set) var createCallCount = 0
    private(set) var logoPathPatches: [LogoPathPatch] = []

    func createBrand(
        name: String,
        englishName: String?,
        isFeatured: Bool,
        websiteURL: String?,
        lookbookArchiveURL: String?,
        moodIDs: [String]
    ) async throws -> BrandCreationReceipt {
        createCallCount += 1
        return BrandCreationReceipt(brandID: "brand-1", discoveryJobID: "discovery-1")
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
        throw CreateBrandTestError.unexpectedCall
    }

    func updateLogoPaths(
        docID: String,
        logoThumbPath: String?,
        logoDetailPath: String?
    ) async throws {
        logoPathPatches.append(
            .init(
                brandID: docID,
                thumbPath: logoThumbPath,
                detailPath: logoDetailPath
            )
        )
    }

    func addBrandManager(
        brandID: BrandID,
        email: String,
        role: BrandManagerRole
    ) async throws -> BrandManagerMutationReceipt {
        throw CreateBrandTestError.unexpectedCall
    }

    func removeBrandManager(
        brandID: BrandID,
        email: String,
        role: BrandManagerRole
    ) async throws -> BrandManagerMutationReceipt {
        throw CreateBrandTestError.unexpectedCall
    }
}

private actor CreateBrandStorageSpy: StorageServiceProtocol {
    private var remainingUploadFailures: Int
    private var failingPaths: Set<String>
    private(set) var uploadedPaths: [String] = []
    private(set) var deletedPaths: [String] = []

    init(
        failingUploadAttempts: Int = 0,
        failingPaths: Set<String> = []
    ) {
        remainingUploadFailures = failingUploadAttempts
        self.failingPaths = failingPaths
    }

    func uploadImage(data: Data, to path: String) async throws -> String {
        uploadedPaths.append(path)
        if remainingUploadFailures > 0 {
            remainingUploadFailures -= 1
            throw CreateBrandTestError.uploadFailed
        }
        if failingPaths.remove(path) != nil {
            throw CreateBrandTestError.uploadFailed
        }
        return path
    }

    func uploadImageFileWithRetryAndDataFallback(
        from fileURL: URL,
        to path: String,
        contentType: String
    ) async throws -> String {
        throw CreateBrandTestError.unexpectedCall
    }

    func uploadVideo(fileURL: URL, to path: String) async throws -> String {
        throw CreateBrandTestError.unexpectedCall
    }

    func uploadImages(
        _ datas: [Data],
        to folderPath: String
    ) async throws -> [String] {
        throw CreateBrandTestError.unexpectedCall
    }

    func downloadData(from path: String, maxSize: Int) async throws -> Data {
        throw CreateBrandTestError.unexpectedCall
    }

    func downloadFile(from path: String, to localURL: URL) async throws {
        throw CreateBrandTestError.unexpectedCall
    }

    func downloadImage(from path: String, maxSize: Int) async throws -> Data {
        throw CreateBrandTestError.unexpectedCall
    }

    func downloadImages(
        _ paths: [String],
        maxSize: Int
    ) async throws -> [Data] {
        throw CreateBrandTestError.unexpectedCall
    }

    func deleteFile(at path: String) async throws {
        deletedPaths.append(path)
    }

    func updateFile(data: Data, at path: String) async throws -> String {
        throw CreateBrandTestError.unexpectedCall
    }

    func updateMetadata(
        for path: String,
        metadata: StorageMetadata
    ) async throws -> StorageMetadata {
        throw CreateBrandTestError.unexpectedCall
    }
}

private struct CreateBrandThumbnailerStub: ImageThumbnailing {
    func makeThumbnailJPEGData(
        from originalJPEGData: Data,
        policy: ThumbnailPolicy
    ) throws -> Data {
        originalJPEGData
    }
}

private struct CreateBrandMoodRepositoryStub: StyleMoodRepositoryProtocol {
    func fetchOnboardingMoods() async throws -> [StyleMood] { [] }
}

private struct CreateBrandMoodAdminRepositoryStub:
    StyleMoodAdminRepositoryProtocol {
    func createMood(_ draft: StyleMoodMutationDraft) async throws -> String {
        throw CreateBrandTestError.unexpectedCall
    }

    func updateMood(
        moodID: String,
        draft: StyleMoodMutationDraft,
        status: StyleMoodStatus
    ) async throws {
        throw CreateBrandTestError.unexpectedCall
    }
}

private enum CreateBrandTestError: LocalizedError {
    case uploadFailed
    case unexpectedCall

    var errorDescription: String? {
        switch self {
        case .uploadFailed:
            return "테스트 업로드 실패"
        case .unexpectedCall:
            return "호출되면 안 되는 테스트 경로"
        }
    }
}
