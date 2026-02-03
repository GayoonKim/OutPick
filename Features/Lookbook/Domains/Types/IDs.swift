//
//  IDs.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

// MARK : - ID 타입 래핑 (테스트/리팩토링에 유리)
struct BrandID: Hashable, Codable { let value: String }
struct SeasonID: Hashable, Codable { let value: String }
struct PostID: Hashable, Codable { let value: String }
struct TagID: Hashable, Codable { let value: String }
struct CommentID: Hashable, Codable { let value: String }
struct ReplacementID: Hashable, Codable { let value: String }
struct UserID: Hashable, Codable { let value: String }
