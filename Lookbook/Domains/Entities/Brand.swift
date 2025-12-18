//
//  Brand.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

// MARK:- 핵심 엔티티들
struct Brand: Equatable, Codable, Identifiable {
    var id: BrandID
    var name: String
    var logoURL: URL?
    var isFeatured: Bool
    var metrics: BrandMetrics
    var updatedAt: Date
}
