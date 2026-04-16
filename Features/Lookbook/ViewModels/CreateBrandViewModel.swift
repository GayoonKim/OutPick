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
    @Published var brandID: String = ""
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

        let docID = normalizedBrandID(brandID)
        guard isValidBrandID(docID) else {
            message = "브랜드 ID는 영문 소문자, 숫자, -, _ 조합의 2~64자로 입력해주세요."
            return
        }

        let rawName = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawName.isEmpty else {
            message = "브랜드명을 입력해주세요."
            return
        }

        isSaving = true
        defer { isSaving = false }

        var uploadedThumbPathForRollback: String?
        var pendingDetailUpload: (path: String, data: Data)?

        do {
            // 1) 이미지가 있으면 Storage에 썸네일만 먼저 업로드(즉시 완료 기준)
            var logoThumbPath: String? = nil

            if let image = selectedLogoImage {
                let thumbPath = "brands/\(docID)/logo/thumb.jpg"
                let detailPath = "brands/\(docID)/logo/detail.jpg"

                if let preparedThumbData = selectedLogoThumbData,
                   let preparedDetailData = selectedLogoDetailData {
                    // 선택 시점 전처리 결과 사용:
                    // - thumb: 즉시 업로드 후 완료 처리
                    // - detail: 백그라운드 업로드
                    let uploadedThumbPath = try await storageService.uploadImage(data: preparedThumbData, to: thumbPath)
                    logoThumbPath = uploadedThumbPath
                    uploadedThumbPathForRollback = uploadedThumbPath
                    pendingDetailUpload = (path: detailPath, data: preparedDetailData)
                } else {
                    // 방어적 fallback(외부에서 UIImage만 직접 주입된 경우)
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

                    let uploadedThumbPath = try await storageService.uploadImage(data: thumbJPEGData, to: thumbPath)
                    logoThumbPath = uploadedThumbPath
                    uploadedThumbPathForRollback = uploadedThumbPath
                    pendingDetailUpload = (path: detailPath, data: detailJPEGData)
                }
            }

            // 2) Firestore에 저장(세부 필드 구성은 store가 책임)
            try await brandStore.upsertBrand(
                docID: docID,
                name: rawName,
                logoThumbPath: logoThumbPath,
                logoDetailPath: nil,
                isFeatured: isFeatured
            )

            uploadedThumbPathForRollback = nil
            if let pendingDetailUpload {
                enqueueDetailUpload(
                    docID: docID,
                    detailPath: pendingDetailUpload.path,
                    detailData: pendingDetailUpload.data
                )
            }
            if logoThumbPath != nil {
                message = "저장 완료: brands/\(docID) (디테일 업로드 중)"
            } else {
                message = "저장 완료: brands/\(docID)"
            }
        } catch {
            if let rollbackPath = uploadedThumbPathForRollback {
                try? await storageService.deleteFile(at: rollbackPath)
            }
            message = "저장 실패: \(error.localizedDescription)"
        }
    }
}

private extension CreateBrandViewModel {
    func normalizedBrandID(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func isValidBrandID(_ value: String) -> Bool {
        guard (2...64).contains(value.count),
              let first = value.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(first) else {
            return false
        }

        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")
        return value.rangeOfCharacter(from: allowedCharacters.inverted) == nil
    }

    func enqueueDetailUpload(docID: String, detailPath: String, detailData: Data) {
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let uploadedDetailPath = try await self.storageService.uploadImage(data: detailData, to: detailPath)
                try await self.brandStore.updateLogoDetailPath(
                    docID: docID,
                    logoDetailPath: uploadedDetailPath
                )
            } catch {
                print("⚠️ 브랜드 detail 업로드/패치 실패(docID=\(docID)): \(error.localizedDescription)")
            }
        }
    }
}
