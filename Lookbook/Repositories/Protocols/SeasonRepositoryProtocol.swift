//
//  SeasonRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation
import FirebaseFirestore

protocol SeasonRepositoryProtocol {
    /// brands/{brandID}/seasons/{seasonID}에 시즌을 생성합니다.
    /// - Parameters:
    ///   - brandID: 브랜드 ID
    ///   - year: 예) 2025
    ///   - term: SS/FW
    ///   - description: 설명(선택)
    ///   - coverImageData: 커버 이미지 Data(선택)
    ///   - tagIDs: 태그 ID 목록(선택)
    ///   - tagConceptIDs: 태그 컨셉 ID 목록(선택)
    func createSeason(
        brandID: BrandID,
        year: Int,
        term: SeasonTerm,
        description: String,
        coverImageData: Data?,
        tagIDs: [TagID],
        tagConceptIDs: [String]?
    ) async throws -> Season

    /// brands/{brandID}/seasons/{seasonID}에서 시즌 1개를 가져옵니다.
    /// - Parameters:
    ///   - brandID: 브랜드 ID
    ///   - seasonID: 시즌 ID
    func fetchSeason(brandID: BrandID, seasonID: SeasonID) async throws -> Season

    /// brands/{brandID}/seasons 컬렉션에서 시즌 목록을 페이지 단위로 가져옵니다.
    /// - Parameters:
    ///   - brandID: 브랜드 ID
    ///   - pageSize: 한 번에 가져올 개수
    ///   - last: 이전 페이지의 마지막 문서 스냅샷(첫 페이지면 nil)
    func fetchSeasons(
        brandID: BrandID,
        pageSize: Int,
        after last: DocumentSnapshot?
    ) async throws -> SeasonPage
    
    /// 시즌 목록은 개수가 적으니,
    /// BrandDetail 같은 화면에서는 전체 로드가 더 단순하고 효율적입니다.
    func fetchAllSeasons(brandID: BrandID) async throws -> [Season]
}
