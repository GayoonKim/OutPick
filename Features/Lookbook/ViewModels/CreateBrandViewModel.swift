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

        isSaving = true
        defer { isSaving = false }

        do {
            let docID = try await brandStore.createBrand(
                name: rawName,
                isFeatured: isFeatured
            )

            do {
                let startedDetailUpload = try await uploadLogoIfNeeded(docID: docID)
                if startedDetailUpload {
                    message = "저장 완료: brands/\(docID) (디테일 업로드 중)"
                } else {
                    message = "저장 완료: brands/\(docID)"
                }
            } catch {
                message = "브랜드는 생성되었지만 로고 업로드에 실패했습니다: \(error.localizedDescription)"
            }
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

    func uploadLogoIfNeeded(docID: String) async throws -> Bool {
        guard let preparedLogo = try prepareLogoUpload() else {
            return false
        }

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
            enqueueDetailUpload(
                docID: docID,
                detailPath: detailPath,
                detailData: preparedLogo.detailData
            )
            return true
        } catch {
            if let rollbackPath = uploadedThumbPathForRollback {
                try? await storageService.deleteFile(at: rollbackPath)
            }
            throw error
        }
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

    func enqueueDetailUpload(docID: String, detailPath: String, detailData: Data) {
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let uploadedDetailPath = try await self.storageService.uploadImage(data: detailData, to: detailPath)
                try await self.brandStore.updateLogoPaths(
                    docID: docID,
                    logoThumbPath: nil,
                    logoDetailPath: uploadedDetailPath
                )
            } catch {
                print("⚠️ 브랜드 detail 업로드/패치 실패(docID=\(docID)): \(error.localizedDescription)")
            }
        }
    }
}
