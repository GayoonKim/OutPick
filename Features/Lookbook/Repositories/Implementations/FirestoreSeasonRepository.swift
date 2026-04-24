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
    private let coverDetailPolicy: ThumbnailPolicy

    /// - Note: RepositoryProvider에서 storage/thumbnailer/policy를 공유 주입하는 것을 권장합니다.
    init(
        db: Firestore = Firestore.firestore(),
        storage: StorageServiceProtocol,
        thumbnailer: ImageThumbnailing,
        coverThumbnailPolicy: ThumbnailPolicy = ThumbnailPolicies.seasonCover,
        coverDetailPolicy: ThumbnailPolicy = ThumbnailPolicies.seasonCoverDetail
    ) {
        self.db = db
        self.storage = storage
        self.thumbnailer = thumbnailer
        self.coverThumbnailPolicy = coverThumbnailPolicy
        self.coverDetailPolicy = coverDetailPolicy
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

        // 2) (선택) 커버 업로드: detail(JPEG) + 썸네일(JPEG)
        var coverPath: String? = nil
        var uploadedDetailPath: String? = nil
        var uploadedThumbPath: String? = nil

        if let coverImageData {
            let detailPath = "brands/\(brandID.value)/seasons/\(seasonID.value)/cover.jpg"
            let thumbPath = "brands/\(brandID.value)/seasons/\(seasonID.value)/cover_thumb.jpg"

            let detailJPEG = try makeJPEGData(
                from: coverImageData,
                policy: coverDetailPolicy
            )
            let thumbJPEG = try makeJPEGData(
                from: coverImageData,
                policy: coverThumbnailPolicy
            )

            // 업로드는 병렬로 수행합니다(네트워크 상황에 따라 체감 속도 개선).
            async let detailUpload: String = storage.uploadImage(data: detailJPEG, to: detailPath)
            async let thumbUpload: String = storage.uploadImage(data: thumbJPEG, to: thumbPath)

            let (dPath, tPath) = try await (detailUpload, thumbUpload)
            uploadedDetailPath = dPath
            uploadedThumbPath = tPath

            // Firestore에는 detail 경로를 저장하고, 썸네일은 규칙으로 파생합니다.
            coverPath = dPath
        }

        // 3) 도메인 모델 생성
        let now = Date()
        let season = Season(
            id: seasonID,
            brandID: brandID,
            displayTitle: Season.formatTitle(year: year, term: term),
            sourceTitle: nil,
            year: year,
            term: term,
            coverPath: coverPath,
            coverRemoteURL: nil,
            description: description,
            tagIDs: tagIDs,
            tagConceptIDs: tagConceptIDs,
            status: .published,
            assetSyncStatus: .ready,
            metadataStatus: .confirmed,
            metadataConfidence: 1,
            sourceURL: nil,
            sourceImportJobID: nil,
            sourceSortIndex: nil,
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
            // 5) Firestore 저장 실패 시 고아 파일 정리(detail + 썸네일)
            if let uploadedDetailPath {
                try? await storage.deleteFile(at: uploadedDetailPath)
            }
            if let uploadedThumbPath {
                try? await storage.deleteFile(at: uploadedThumbPath)
            }
            throw error
        }
    }

    private func makeJPEGData(from inputData: Data, policy: ThumbnailPolicy) throws -> Data {
        do {
            return try thumbnailer.makeThumbnailJPEGData(
                from: inputData,
                policy: policy
            )
        } catch {
            guard let uiImage = UIImage(data: inputData) else {
                throw NSError(domain: "FirestoreSeasonRepository", code: -10, userInfo: [
                    NSLocalizedDescriptionKey: "커버 이미지를 디코딩하지 못했습니다."
                ])
            }
            guard let normalizedJPEG = uiImage.jpegData(compressionQuality: 0.95) else {
                throw NSError(domain: "FirestoreSeasonRepository", code: -11, userInfo: [
                    NSLocalizedDescriptionKey: "커버 이미지를 JPEG로 변환하지 못했습니다."
                ])
            }
            return try thumbnailer.makeThumbnailJPEGData(
                from: normalizedJPEG,
                policy: policy
            )
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
