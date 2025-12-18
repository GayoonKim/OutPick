//
//  SeasonRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

protocol SeasonRepositoryProtocol {
    func fetchSeasons(brandID: BrandID) async throws -> [Season]
    func fetchSeason(brandID: BrandID, seasonID: SeasonID) async throws -> Season
}
