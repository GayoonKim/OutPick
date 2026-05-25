//
//  BrandUserStateRepositoryProtocol.swift
//  OutPick
//
//  Created by Codex on 5/25/26.
//

import Foundation

protocol BrandUserStateRepositoryProtocol {
    func fetchBrandUserState(
        userID: UserID,
        brandID: BrandID
    ) async throws -> BrandUserState?
}
