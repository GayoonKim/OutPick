//
//  CreateBrandViewModel.swift
//  OutPick
//
//  Created by 김가윤 on 1/13/26.
//

import Foundation
import SwiftUI
import UIKit

@MainActor
final class CreateBrandViewModel: ObservableObject {

    struct CreatedBrand: Equatable {
        let id: BrandID
        let name: String
        let englishName: String?
        let websiteURL: String?
        let lookbookArchiveURL: String?
        let discoveryJobID: String?
        let hasLogoAsset: Bool
        let moodIDs: [String]

        init(
            id: BrandID,
            name: String,
            englishName: String?,
            websiteURL: String?,
            lookbookArchiveURL: String?,
            discoveryJobID: String? = nil,
            hasLogoAsset: Bool,
            moodIDs: [String] = []
        ) {
            self.id = id
            self.name = name
            self.englishName = englishName
            self.websiteURL = websiteURL
            self.lookbookArchiveURL = lookbookArchiveURL
            self.discoveryJobID = discoveryJobID
            self.hasLogoAsset = hasLogoAsset
            self.moodIDs = moodIDs
        }

        var canDiscoverSeasons: Bool {
            guard let lookbookArchiveURL else { return false }
            return lookbookArchiveURL.isEmpty == false
        }
    }

    // MARK: - 입력 상태
    @Published var brandName: String = ""
    @Published var englishName: String = ""
    @Published var websiteURLText: String = ""
    @Published var lookbookArchiveURLText: String = ""
    @Published var selectedLogoImage: UIImage? = nil
    @Published var isFeatured: Bool = false
    @Published private(set) var moods: [StyleMood] = []
    @Published var selectedMoodIDs: Set<String> = []

    // MARK: - UI 상태
    @Published var isSaving: Bool = false
    @Published private(set) var isLoadingMoods: Bool = false
    @Published private(set) var isCreatingMood: Bool = false
    @Published private(set) var createdBrandDocument: CreatedBrand?
    @Published var message: String? = nil

    private let brandStore: BrandStoringRepository
    private let storageService: StorageServiceProtocol
    private let thumbnailer: ImageThumbnailing
    private let moodRepository: StyleMoodRepositoryProtocol
    private let moodAdminRepository: StyleMoodAdminRepositoryProtocol

    // 선택 직후 전처리된 업로드 입력
    private var selectedLogoThumbData: Data?
    private var selectedLogoDetailData: Data?

    init(
        initialBrandName: String? = nil,
        initialEnglishName: String? = nil,
        brandStore: BrandStoringRepository,
        storageService: StorageServiceProtocol,
        thumbnailer: ImageThumbnailing,
        moodRepository: StyleMoodRepositoryProtocol =
            FirestoreStyleMoodRepository(db: .firestore()),
        moodAdminRepository: StyleMoodAdminRepositoryProtocol =
            CloudFunctionsStyleMoodAdminRepository()
    ) {
        self.brandStore = brandStore
        self.storageService = storageService
        self.thumbnailer = thumbnailer
        self.moodRepository = moodRepository
        self.moodAdminRepository = moodAdminRepository
        self.brandName = initialBrandName ?? ""
        self.englishName = initialEnglishName ?? ""
    }

    func setPickedLogo(
        thumbImage: UIImage,
        thumbData: Data,
        detailData: Data
    ) {
        selectedLogoImage = thumbImage
        selectedLogoThumbData = thumbData
        selectedLogoDetailData = detailData
    }

    func clearPickedLogo() {
        selectedLogoImage = nil
        selectedLogoThumbData = nil
        selectedLogoDetailData = nil
    }

    func loadMoods() async {
        isLoadingMoods = true
        defer { isLoadingMoods = false }
        do {
            moods = try await moodRepository.fetchOnboardingMoods()
        } catch {
            message = "브랜드 스타일을 불러오지 못했습니다: \(error.localizedDescription)"
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
            await loadMoods()
            selectedMoodIDs.insert(moodID)
            return true
        } catch {
            message = "스타일 키워드를 추가하지 못했습니다: \(error.localizedDescription)"
            return false
        }
    }

    func saveBrand() async -> CreatedBrand? {
        message = nil

        let rawName = normalizedDisplayName(brandName)
        guard !rawName.isEmpty else {
            message = "브랜드명을 입력해주세요."
            return nil
        }
        let rawEnglishName = normalizedDisplayName(englishName)

        let websiteURL: String
        let lookbookArchiveURL: String
        do {
            websiteURL = try normalizedHTTPURL(
                websiteURLText,
                fieldLabel: "공식 홈페이지 URL"
            ) ?? ""
            lookbookArchiveURL = try normalizedHTTPURL(
                lookbookArchiveURLText,
                fieldLabel: "룩북 목록 URL"
            ) ?? ""
        } catch {
            message = error.localizedDescription
            return nil
        }

        isSaving = true
        defer { isSaving = false }

        let createdBrand: CreatedBrand
        if let createdBrandDocument {
            createdBrand = createdBrandDocument
        } else {
            do {
                let normalizedWebsiteURL = websiteURL.isEmpty ? nil : websiteURL
                let normalizedLookbookArchiveURL = lookbookArchiveURL.isEmpty
                    ? nil
                    : lookbookArchiveURL
                let receipt = try await brandStore.createBrand(
                    name: rawName,
                    englishName: rawEnglishName.isEmpty ? nil : rawEnglishName,
                    isFeatured: isFeatured,
                    websiteURL: normalizedWebsiteURL,
                    lookbookArchiveURL: normalizedLookbookArchiveURL,
                    moodIDs: orderedSelectedMoodIDs
                )
                createdBrand = CreatedBrand(
                    id: BrandID(value: receipt.brandID),
                    name: rawName,
                    englishName: rawEnglishName.isEmpty ? nil : rawEnglishName,
                    websiteURL: normalizedWebsiteURL,
                    lookbookArchiveURL: normalizedLookbookArchiveURL,
                    discoveryJobID: receipt.discoveryJobID,
                    hasLogoAsset: false,
                    moodIDs: orderedSelectedMoodIDs
                )
                createdBrandDocument = createdBrand
            } catch {
                message = "저장 실패: \(error.localizedDescription)"
                return nil
            }
        }

        guard selectedLogoImage != nil else {
            return createdBrand
        }

        do {
            try await uploadLogo(docID: createdBrand.id.value)
            let completedBrand = CreatedBrand(
                id: createdBrand.id,
                name: createdBrand.name,
                englishName: createdBrand.englishName,
                websiteURL: createdBrand.websiteURL,
                lookbookArchiveURL: createdBrand.lookbookArchiveURL,
                discoveryJobID: createdBrand.discoveryJobID,
                hasLogoAsset: true,
                moodIDs: createdBrand.moodIDs
            )
            createdBrandDocument = completedBrand
            return completedBrand
        } catch {
            message = "브랜드는 생성됐지만 로고를 저장하지 못했습니다. 다시 시도해주세요: \(error.localizedDescription)"
            return nil
        }
    }
}

private extension CreateBrandViewModel {
    var orderedSelectedMoodIDs: [String] {
        moods
            .filter { selectedMoodIDs.contains($0.id) }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.id < $1.id
            }
            .map(\.id)
    }

    struct PreparedLogoUpload {
        let thumbData: Data
        let detailData: Data
    }

    func normalizedDisplayName(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    func normalizedHTTPURL(_ rawValue: String, fieldLabel: String) throws -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 한국어 주석: 사용자가 도메인만 입력한 경우를 위해 https 스킴을 보정합니다.
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"

        guard var components = URLComponents(string: candidate) else {
            throw NSError(
                domain: "CreateBrandViewModel",
                code: -20,
                userInfo: [NSLocalizedDescriptionKey: "\(fieldLabel) 형식이 올바르지 않습니다."]
            )
        }

        guard let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw NSError(
                domain: "CreateBrandViewModel",
                code: -21,
                userInfo: [NSLocalizedDescriptionKey: "\(fieldLabel)은 http 또는 https로 시작해야 합니다."]
            )
        }

        guard let host = components.host, !host.isEmpty else {
            throw NSError(
                domain: "CreateBrandViewModel",
                code: -22,
                userInfo: [NSLocalizedDescriptionKey: "\(fieldLabel)에 도메인이 필요합니다."]
            )
        }

        components.scheme = scheme
        components.host = host.lowercased()

        guard let normalized = components.string else {
            throw NSError(
                domain: "CreateBrandViewModel",
                code: -23,
                userInfo: [NSLocalizedDescriptionKey: "\(fieldLabel)을 정규화하지 못했습니다."]
            )
        }

        return normalized
    }

    func prepareLogoUpload() throws -> PreparedLogoUpload? {
        guard let image = selectedLogoImage else {
            return nil
        }

        if let preparedThumbData = selectedLogoThumbData,
           let preparedDetailData = selectedLogoDetailData {
            return PreparedLogoUpload(
                thumbData: preparedThumbData,
                detailData: preparedDetailData
            )
        }

        guard let originalJPEGData = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "CreateBrandViewModel", code: -10, userInfo: [
                NSLocalizedDescriptionKey: "원본 이미지를 JPEG 데이터로 변환하지 못했습니다."
            ])
        }

        let thumbJPEGData = try thumbnailer.makeThumbnailJPEGData(
            from: originalJPEGData,
            policy: ThumbnailPolicies.brandLogoList
        )
        let detailJPEGData = try thumbnailer.makeThumbnailJPEGData(
            from: originalJPEGData,
            policy: ThumbnailPolicies.brandLogoDetail
        )

        return PreparedLogoUpload(
            thumbData: thumbJPEGData,
            detailData: detailJPEGData
        )
    }

    func uploadLogo(docID: String) async throws {
        guard let preparedLogo = try prepareLogoUpload() else { return }

        let thumbPath = "brands/\(docID)/logo/thumb.jpg"
        let detailPath = "brands/\(docID)/logo/detail.jpg"
        var uploadedPaths: [String] = []

        do {
            let uploadedThumbPath = try await storageService.uploadImage(
                data: preparedLogo.thumbData,
                to: thumbPath
            )
            uploadedPaths.append(uploadedThumbPath)

            let uploadedDetailPath = try await storageService.uploadImage(
                data: preparedLogo.detailData,
                to: detailPath
            )
            uploadedPaths.append(uploadedDetailPath)

            try await brandStore.updateLogoPaths(
                docID: docID,
                logoThumbPath: uploadedThumbPath,
                logoDetailPath: uploadedDetailPath
            )
        } catch {
            for path in uploadedPaths {
                try? await storageService.deleteFile(at: path)
            }
            throw error
        }
    }
}
