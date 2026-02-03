//
//  Tag.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

struct Tag: Equatable, Codable, Identifiable {
    var id: TagID
    var name: String
    var normalized: String? // 검색/ 중복 방지용
}
