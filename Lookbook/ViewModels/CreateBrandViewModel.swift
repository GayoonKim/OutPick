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

    init(
        brandStore: BrandStoringRepository,
        storageService: StorageServiceProtocol,
        thumbnailer: ImageThumbnailing
    ) {
        self.brandStore = brandStore
        self.storageService = storageService
        self.thumbnailer = thumbnailer
    }

    func saveBrand() async {
        message = nil

        let rawName = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawName.isEmpty else {
            message = "브랜드명을 입력해주세요."
            return
        }

        // 한국어 주석: Firestore 문서 ID는 자동 생성(랜덤)으로 사용합니다.
        let docID = brandStore.makeNewBrandDocumentID()

        isSaving = true
        defer { isSaving = false }

        do {
            // 1) 이미지가 있으면 Storage에 (썸네일 + 원본) 업로드하고 경로 확보
            var logoThumbPath: String? = nil
            var logoOriginalPath: String? = nil

            if let image = selectedLogoImage {
                let thumbPath = "brands/\(docID)/logo/thumb.jpg"
                let originalPath = "brands/\(docID)/logo/original.jpg"

                // 한국어 주석: 원본 업로드(화질 우선)
                guard let originalJPEGData = image.jpegData(compressionQuality: 0.9) else {
                    throw NSError(domain: "CreateBrandViewModel", code: -10, userInfo: [
                        NSLocalizedDescriptionKey: "원본 이미지를 JPEG 데이터로 변환하지 못했습니다."
                    ])
                }

                // 한국어 주석: 업로드는 path 기반으로 처리하고, DB에는 path를 저장합니다.
                logoOriginalPath = try await storageService.uploadImage(data: originalJPEGData, to: originalPath)

                // 한국어 주석: 썸네일 생성 후 업로드(목록/카드용)
                let policy = ThumbnailPolicies.brandLogoList
                let thumbJPEGData = try thumbnailer.makeThumbnailJPEGData(from: originalJPEGData, policy: policy)
                logoThumbPath = try await storageService.uploadImage(data: thumbJPEGData, to: thumbPath)
            }

            // 2) Firestore에 저장(세부 필드 구성은 store가 책임)
            try await brandStore.upsertBrand(
                docID: docID,
                name: rawName,
                logoThumbPath: logoThumbPath,
                logoOriginalPath: logoOriginalPath,
                isFeatured: isFeatured
            )

            message = "저장 완료: brands/\(docID)"
        } catch {
            message = "저장 실패: \(error.localizedDescription)"
        }
    }
}
