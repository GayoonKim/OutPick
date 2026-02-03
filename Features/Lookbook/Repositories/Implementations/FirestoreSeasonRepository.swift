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

        // 2) (선택) 커버 업로드: 원본(Data 그대로) + 썸네일(JPEG)
        var coverPath: String? = nil
        var uploadedOriginalPath: String? = nil
        var uploadedThumbPath: String? = nil

        if let coverImageData {
            // 원본은 확장자에 의존하지 않도록 고정 이름으로 저장합니다.
            // (coverImageData가 JPEG/PNG/HEIC 등 어떤 포맷이든 그대로 업로드)
            let originalPath = "brands/\(brandID.value)/seasons/\(seasonID.value)/cover"
            let thumbPath = originalPath + "_thumb.jpg"

            // 썸네일은 가능하면 입력 Data에서 바로 생성하고,
            // thumbnailer가 특정 포맷(JPEG 등)만 기대해 실패하는 경우에만 JPEG로 정규화 후 재시도합니다.
            let thumbJPEG: Data
            do {
                thumbJPEG = try thumbnailer.makeThumbnailJPEGData(
                    from: coverImageData,
                    policy: coverThumbnailPolicy
                )
            } catch {
                guard let uiImage = UIImage(data: coverImageData) else {
                    throw NSError(domain: "FirestoreSeasonRepository", code: -10, userInfo: [
                        NSLocalizedDescriptionKey: "커버 이미지를 디코딩하지 못했습니다."
                    ])
                }
                guard let normalizedJPEG = uiImage.jpegData(compressionQuality: 0.95) else {
                    throw NSError(domain: "FirestoreSeasonRepository", code: -11, userInfo: [
                        NSLocalizedDescriptionKey: "커버 이미지를 JPEG로 변환하지 못했습니다."
                    ])
                }
                thumbJPEG = try thumbnailer.makeThumbnailJPEGData(
                    from: normalizedJPEG,
                    policy: coverThumbnailPolicy
                )
            }

            // 업로드는 병렬로 수행합니다(네트워크 상황에 따라 체감 속도 개선).
            async let originalUpload: String = storage.uploadImage(data: coverImageData, to: originalPath)
            async let thumbUpload: String = storage.uploadImage(data: thumbJPEG, to: thumbPath)

            let (oPath, tPath) = try await (originalUpload, thumbUpload)
            uploadedOriginalPath = oPath
            uploadedThumbPath = tPath

            // Firestore에는 원본 경로만 저장(썸네일은 규칙으로 파생).
            coverPath = tPath
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
            if let uploadedOriginalPath {
                try? await storage.deleteFile(at: uploadedOriginalPath)
            }
            if let uploadedThumbPath {
                try? await storage.deleteFile(at: uploadedThumbPath)
            }
            throw error
        }
    }
    
    func fetchSeason(brandID: BrandID, seasonID: SeasonID) async throws -> Season {
        let snapshot = try await db
            .collection("brands").document(brandID.value)
            .collection("seasons").document(seasonID.value)
            .getDocument()

        // 문서가 존재하지 않으면 명확하게 실패 처리합니다.
        guard snapshot.exists else {
            throw NSError(domain: "FirestoreSeasonRepository", code: -20, userInfo: [
                NSLocalizedDescriptionKey: "해당 시즌 문서가 존재하지 않습니다."
            ])
        }

        // 스냅샷 → DTO 디코딩
        let dto: SeasonDTO = try FirestoreMapper.mapDocument(snapshot)

        // DTO → Domain 변환(brandID는 상위 경로에서 주입)
        return try dto.toDomain(brandID: brandID)
    }

    func fetchSeasons(
        brandID: BrandID,
        pageSize: Int,
        after last: DocumentSnapshot?
    ) async throws -> SeasonPage {

        // pageSize가 이상하면 빠르게 실패 처리
        guard pageSize > 0 else {
            throw NSError(domain: "FirestoreSeasonRepository", code: -30, userInfo: [
                NSLocalizedDescriptionKey: "pageSize는 1 이상이어야 합니다."
            ])
        }

        var query: Query = db
            .collection("brands").document(brandID.value)
            .collection("seasons")
            .order(by: "createdAt", descending: true)
            .limit(to: pageSize)

        // 다음 페이지라면 커서 적용
        if let last {
            query = query.start(afterDocument: last)
        }

        let snapshot = try await query.getDocuments()

        let items: [Season] = try snapshot.documents.map { doc in
            let dto: SeasonDTO = try FirestoreMapper.mapDocument(doc)
            return try dto.toDomain(brandID: brandID)
        }

        // 다음 페이지 커서(없으면 nil)
        let nextLast = snapshot.documents.last

        return SeasonPage(items: items, last: nextLast)
    }
    
    func fetchAllSeasons(brandID: BrandID) async throws -> [Season] {
        let snapshot = try await db
            .collection("brands").document(brandID.value)
            .collection("seasons")
            // 서버 정렬은 가볍게 createdAt 기준으로만 두고,
            // 실제 화면 목적(연도/텀 기반)은 클라이언트에서 Season.defaultSort로 정렬합니다.
            .order(by: "createdAt", descending: true)
            .getDocuments()

        return try snapshot.documents.map { doc in
            let dto: SeasonDTO = try FirestoreMapper.mapDocument(doc)
            return try dto.toDomain(brandID: brandID)
        }
    }
}

struct SeasonPage {
    let items: [Season]
    let last: DocumentSnapshot?
}
