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

    func fetchSeasons(brandID: BrandID) async throws -> [Season] {
        let snap = try await db
            .collection("brands")
            .document(brandID.value)
            .collection("seasons")
            .order(by: "updatedAt", descending: true)
            .getDocuments()

        let dtos: [SeasonDTO] = try snap.documents.map { try FirestoreMapper.mapDocument($0) }
        return try dtos.map { try $0.toDomain(brandID: brandID) }
    }

    func fetchSeason(brandID: BrandID, seasonID: SeasonID) async throws -> Season {
        let doc = try await db
            .collection("brands")
            .document(brandID.value)
            .collection("seasons")
            .document(seasonID.value)
            .getDocument()

        let dto: SeasonDTO = try FirestoreMapper.mapDocument(doc)
        return try dto.toDomain(brandID: brandID)
    }
}
