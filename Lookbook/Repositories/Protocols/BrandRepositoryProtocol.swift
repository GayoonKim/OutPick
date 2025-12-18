//
//  BrandRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

import Foundation

protocol BrandRepositoryProtocol {
    func fetchBrands() async throws -> [Brand]
    func fetchFeaturedBrands(limit: Int) async throws -> [Brand]
    func fetchBrand(brandID: BrandID) async throws -> Brand
}
