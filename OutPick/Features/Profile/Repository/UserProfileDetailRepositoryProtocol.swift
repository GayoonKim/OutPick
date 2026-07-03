//
//  UserProfileDetailRepositoryProtocol.swift
//  OutPick
//

import Foundation

protocol UserProfileDetailRepositoryProtocol {
    func fetchUserProfile(userID: String) async throws -> UserProfile
}
