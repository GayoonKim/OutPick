//
//  TagAliasRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 1/10/26.
//

import Foundation

protocol TagAliasRepositoryProtocol {
    /// /tagAliases에서 prefix 검색 (raw/displayName 기준)
    func searchAliases(prefix: String, limit: Int) async throws -> [TagAlias]
}
