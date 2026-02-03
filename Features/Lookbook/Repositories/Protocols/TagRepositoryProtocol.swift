//
//  TagRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

protocol TagRepositoryProtocol {
    func fetchTag(tagID: TagID) async throws -> Tag
    func fetchTags(tagIDs: [TagID]) async throws -> [Tag]
    
    /// /tags에서 prefix 검색 (normalized 기반)
    func searchTags(prefix: String, limit: Int) async throws -> [Tag]
}
