//
//  UserProfileDetailRepositoryProtocol.swift
//  OutPick
//

import Foundation

protocol UserProfileDetailRepositoryProtocol {
    func fetchUserProfile(email: String) async throws -> UserProfile
    func fetchUserProfile(userID: String) async throws -> UserProfile
}
