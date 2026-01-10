//
//  SeasonRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

protocol SeasonRepositoryProtocol {
    /// brands/{brandID}/seasons/{seasonID}에 시즌을 생성합니다.
    /// - Parameters:
    ///   - brandID: 브랜드 ID
    ///   - year: 예) 2025
    ///   - term: SS/FW
    ///   - description: 설명(선택)
    ///   - coverImageData: 커버 이미지 Data(선택)
        func createSeason(brandID: BrandID, year: Int, term: SeasonTerm, description: String, coverImageData: Data?, tagIDs: [TagID], tagConceptIDs: [String]?) async throws -> Season
}
