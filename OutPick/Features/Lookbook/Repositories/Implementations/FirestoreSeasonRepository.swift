//
//  FirestoreSeasonRepository.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

final class FirestoreSeasonRepository: SeasonRepositoryProtocol {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
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
        let season = try dto.toDomain(
            documentID: snapshot.documentID,
            brandID: brandID
        )
        guard season.isVisibleToUsers else {
            throw LookbookContentUnavailableError.seasonUnavailable
        }
        return season
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

        let items: [Season] = try snapshot.documents.compactMap { doc in
            let dto: SeasonDTO = try FirestoreMapper.mapDocument(doc)
            let season = try dto.toDomain(
                documentID: doc.documentID,
                brandID: brandID
            )
            return season.isVisibleToUsers ? season : nil
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

        return try snapshot.documents.compactMap { doc in
            let dto: SeasonDTO = try FirestoreMapper.mapDocument(doc)
            let season = try dto.toDomain(
                documentID: doc.documentID,
                brandID: brandID
            )
            return season.isVisibleToUsers ? season : nil
        }
    }
}

struct SeasonPage {
    let items: [Season]
    let last: DocumentSnapshot?
}
