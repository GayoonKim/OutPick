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

    // MARK: - 입력 상태
    @Published var brandName: String = ""
    @Published var websiteURLText: String = ""
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

    func saveBrand() async {
        message = nil

        let rawName = normalizedDisplayName(brandName)
        guard !rawName.isEmpty else {
            message = "브랜드명을 입력해주세요."
            return
        }

        let websiteURL: String
        do {
            websiteURL = try normalizedWebsiteURL(websiteURLText) ?? ""
        } catch {
            message = error.localizedDescription
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let docID = try await brandStore.createBrand(
                name: rawName,
                isFeatured: isFeatured,
                websiteURL: websiteURL.isEmpty ? nil : websiteURL
            )

            enqueueLogoUploadIfNeeded(docID: docID)
            message = "저장 완료: brands/\(docID) (리소스 준비 중)"
        } catch {
            message = "저장 실패: \(error.localizedDescription)"
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

    func normalizedWebsiteURL(_ rawValue: String) throws -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 한국어 주석: 사용자가 도메인만 입력한 경우를 위해 https 스킴을 보정합니다.
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"

        guard var components = URLComponents(string: candidate) else {
            throw NSError(
                domain: "CreateBrandViewModel",
                code: -20,
                userInfo: [NSLocalizedDescriptionKey: "브랜드 URL 형식이 올바르지 않습니다."]
            )
        }

        guard let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw NSError(
                domain: "CreateBrandViewModel",
                code: -21,
                userInfo: [NSLocalizedDescriptionKey: "브랜드 URL은 http 또는 https로 시작해야 합니다."]
            )
        }

        guard let host = components.host, !host.isEmpty else {
            throw NSError(
                domain: "CreateBrandViewModel",
                code: -22,
                userInfo: [NSLocalizedDescriptionKey: "브랜드 URL에 도메인이 필요합니다."]
            )
        }

        components.scheme = scheme
        components.host = host.lowercased()

        guard let normalized = components.string else {
            throw NSError(
                domain: "CreateBrandViewModel",
                code: -23,
                userInfo: [NSLocalizedDescriptionKey: "브랜드 URL을 정규화하지 못했습니다."]
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

        Task(priority: .utility) { [weak self] in
            guard let self else { return }

            let thumbPath = "brands/\(docID)/logo/thumb.jpg"
            let detailPath = "brands/\(docID)/logo/detail.jpg"
            var uploadedThumbPathForRollback: String?

            do {
                let uploadedThumbPath = try await self.storageService.uploadImage(
                    data: preparedLogo.thumbData,
                    to: thumbPath
                )
                uploadedThumbPathForRollback = uploadedThumbPath

                try await self.brandStore.updateLogoPaths(
                    docID: docID,
                    logoThumbPath: uploadedThumbPath,
                    logoDetailPath: nil
                )

                uploadedThumbPathForRollback = nil

                let uploadedDetailPath = try await self.storageService.uploadImage(
                    data: preparedLogo.detailData,
                    to: detailPath
                )
                try await self.brandStore.updateLogoPaths(
                    docID: docID,
                    logoThumbPath: nil,
                    logoDetailPath: uploadedDetailPath
                )
            } catch {
                if let rollbackPath = uploadedThumbPathForRollback {
                    try? await self.storageService.deleteFile(at: rollbackPath)
                }
                print("⚠️ 브랜드 로고 업로드/패치 실패(docID=\(docID)): \(error.localizedDescription)")
            }
        }
    }
}
