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
        let websiteURL: String?
        let lookbookArchiveURL: String?
        let hasLogoAsset: Bool

        var canDiscoverSeasons: Bool {
            guard let lookbookArchiveURL else { return false }
            return lookbookArchiveURL.isEmpty == false
        }
    }

    // MARK: - 입력 상태
    @Published var brandName: String = ""
    @Published var websiteURLText: String = ""
    @Published var lookbookArchiveURLText: String = ""
    @Published var selectedLogoImage: UIImage? = nil
    @Published var isFeatured: Bool = false

    // MARK: - UI 상태
    @Published var isSaving: Bool = false
    @Published var message: String? = nil

    private let brandStore: BrandStoringRepository
    private let storageService: StorageServiceProtocol
    private let thumbnailer: ImageThumbnailing

    // 선택 직후 전처리된 업로드 입력
    private var selectedLogoThumbData: Data?
    private var selectedLogoDetailData: Data?

    init(
        brandStore: BrandStoringRepository,
        storageService: StorageServiceProtocol,
        thumbnailer: ImageThumbnailing
    ) {
        self.brandStore = brandStore
        self.storageService = storageService
        self.thumbnailer = thumbnailer
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

    func saveBrand() async -> CreatedBrand? {
        message = nil

        let rawName = normalizedDisplayName(brandName)
        guard !rawName.isEmpty else {
            message = "브랜드명을 입력해주세요."
            return nil
        }

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

        do {
            let normalizedWebsiteURL = websiteURL.isEmpty ? nil : websiteURL
            let normalizedLookbookArchiveURL = lookbookArchiveURL.isEmpty
                ? nil
                : lookbookArchiveURL
            let docID = try await brandStore.createBrand(
                name: rawName,
                isFeatured: isFeatured,
                websiteURL: normalizedWebsiteURL,
                lookbookArchiveURL: normalizedLookbookArchiveURL
            )

            enqueueLogoUploadIfNeeded(docID: docID)
            return CreatedBrand(
                id: BrandID(value: docID),
                name: rawName,
                websiteURL: normalizedWebsiteURL,
                lookbookArchiveURL: normalizedLookbookArchiveURL,
                hasLogoAsset: selectedLogoImage != nil
            )
        } catch {
            message = "저장 실패: \(error.localizedDescription)"
            return nil
        }
    }
}

private extension CreateBrandViewModel {
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

    func enqueueLogoUploadIfNeeded(docID: String) {
        let preparedLogo: PreparedLogoUpload?

        do {
            preparedLogo = try prepareLogoUpload()
        } catch {
            print("⚠️ 브랜드 로고 준비 실패(docID=\(docID)): \(error.localizedDescription)")
            return
        }

        guard let preparedLogo else { return }

        let storageService = self.storageService
        let brandStore = self.brandStore

        Task(priority: .utility) {
            let thumbPath = "brands/\(docID)/logo/thumb.jpg"
            let detailPath = "brands/\(docID)/logo/detail.jpg"
            var uploadedThumbPathForRollback: String?

            do {
                let uploadedThumbPath = try await storageService.uploadImage(
                    data: preparedLogo.thumbData,
                    to: thumbPath
                )
                uploadedThumbPathForRollback = uploadedThumbPath

                try await brandStore.updateLogoPaths(
                    docID: docID,
                    logoThumbPath: uploadedThumbPath,
                    logoDetailPath: nil
                )

                uploadedThumbPathForRollback = nil

                let uploadedDetailPath = try await storageService.uploadImage(
                    data: preparedLogo.detailData,
                    to: detailPath
                )
                try await brandStore.updateLogoPaths(
                    docID: docID,
                    logoThumbPath: nil,
                    logoDetailPath: uploadedDetailPath
                )
            } catch {
                if let rollbackPath = uploadedThumbPathForRollback {
                    try? await storageService.deleteFile(at: rollbackPath)
                }
                print("⚠️ 브랜드 로고 업로드/패치 실패(docID=\(docID)): \(error.localizedDescription)")
            }
        }
    }
}
