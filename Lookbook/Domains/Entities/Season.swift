//
//  Season.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

struct Season: Equatable, Codable, Identifiable {
    var id: SeasonID
    var brandID: BrandID
    var title: String       // 예: "25 F/W"
    var coverURL: URL?
    var startDate: Date?
    var endDate: Date?
    var updatedAt: Date
}
