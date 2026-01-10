//
//  FirestoreSeasonRepository.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore
import UIKit

final class FirestoreSeasonRepository: SeasonRepositoryProtocol {

    private let db: Firestore
    private let storage: StorageServiceProtocol
    private let thumbnailer: ImageThumbnailing
    private let coverThumbnailPolicy: ThumbnailPolicy

    /// - Note: RepositoryProvider에서 storage/thumbnailer/policy를 공유 주입하는 것을 권장합니다.
    init(
        db: Firestore = Firestore.firestore(),
        storage: StorageServiceProtocol,
        thumbnailer: ImageThumbnailing,
        coverThumbnailPolicy: ThumbnailPolicy = ThumbnailPolicies.seasonCover
    ) {
        self.db = db
        self.storage = storage
        self.thumbnailer = thumbnailer
        self.coverThumbnailPolicy = coverThumbnailPolicy
    }

    func createSeason(
        brandID: BrandID,
        year: Int,
        term: SeasonTerm,
        description: String,
        coverImageData: Data?,
        tagIDs: [TagID],
        tagConceptIDs: [String]?
    ) async throws -> Season {

        // 1) 문서 ID 선점
        let seasonRef = db
            .collection("brands")
            .document(brandID.value)
            .collection("seasons")
            .document()

        let seasonID = SeasonID(value: seasonRef.documentID)

        // 2) (선택) 커버 업로드: 원본 + 썸네일
        var coverPath: String? = nil

        if let coverImageData {
            let originalPath = "brands/\(brandID.value)/seasons/\(seasonID.value)/cover.jpg"
            let thumbPath = "brands/\(brandID.value)/seasons/\(seasonID.value)/cover_thumb.jpg"

            // 한국어 주석: 원본이 PNG/HEIC일 수 있으므로 JPEG로 통일
            guard let uiImage = UIImage(data: coverImageData) else {
                throw NSError(domain: "FirestoreSeasonRepository", code: -10, userInfo: [
                    NSLocalizedDescriptionKey: "커버 이미지를 디코딩하지 못했습니다."
                ])
            }

            // 한국어 주석: 원본 JPEG 생성(고품질)
            guard let originalJPEG = uiImage.jpegData(compressionQuality: 0.95) else {
                throw NSError(domain: "FirestoreSeasonRepository", code: -11, userInfo: [
                    NSLocalizedDescriptionKey: "커버 이미지를 JPEG로 변환하지 못했습니다."
                ])
            }

            // 한국어 주석: 주입된 thumbnailer + policy로 썸네일 생성
            let thumbJPEG = try thumbnailer.makeThumbnailJPEGData(
                from: originalJPEG,
                policy: coverThumbnailPolicy
            )

            // 한국어 주석: 업로드(원본 → 썸네일)
            _ = try await storage.uploadImage(data: originalJPEG, to: originalPath)
            _ = try await storage.uploadImage(data: thumbJPEG, to: thumbPath)

            // 한국어 주석: Firestore에는 원본 경로만 저장(썸네일은 규칙으로 파생)
            coverPath = originalPath
        }

        // 3) 도메인 모델 생성
        let now = Date()
        let season = Season(
            id: seasonID,
            brandID: brandID,
            year: year,
            term: term,
            coverPath: coverPath,
            description: description,
            tagIDs: tagIDs,
            tagConceptIDs: tagConceptIDs,
            status: .published,
            postCount: 0,
            createdAt: now,
            updatedAt: now
        )

        // 4) Firestore 저장
        do {
            let dto = SeasonDTO.fromDomain(season)
            try seasonRef.setData(from: dto, merge: false)
            return season
        } catch {
            // 5) Firestore 저장 실패 시 고아 파일 정리(원본 + 썸네일)
            if let coverPath {
                try? await storage.deleteFile(at: coverPath)

                let thumbPath: String
                if coverPath.hasSuffix("/cover.jpg") {
                    thumbPath = coverPath.replacingOccurrences(of: "/cover.jpg", with: "/cover_thumb.jpg")
                } else if coverPath.contains("/cover.") {
                    thumbPath = coverPath.replacingOccurrences(of: "/cover.", with: "/cover_thumb.")
                } else {
                    thumbPath = coverPath + "_thumb"
                }

                try? await storage.deleteFile(at: thumbPath)
            }
            throw error
        }
    }
}
