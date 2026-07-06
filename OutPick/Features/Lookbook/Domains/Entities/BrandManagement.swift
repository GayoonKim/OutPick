//
//  BrandManagement.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

enum BrandManagerRole: String, CaseIterable, Identifiable {
    case owner
    case admin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .owner:
            return "Owner"
        case .admin:
            return "Admin"
        }
    }
}

struct BrandManagerMutationReceipt: Equatable {
    let brandID: BrandID
    let userID: UserID
    let email: String
    let role: BrandManagerRole
    let duplicate: Bool
    let removed: Bool
}
