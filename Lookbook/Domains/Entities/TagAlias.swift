//
//  TagAlias.swift
//  OutPick
//
//  Created by 김가윤 on 1/10/26.
//

import Foundation

/// /tagAliases/{aliasId} (aliasId는 보통 raw와 동일하게 관리해도 됨)
/// 예: /tagAliases/스트리트 -> conceptId: concept_streetwear
struct TagAlias: Equatable, Codable, Identifiable {
    /// Firestore DocumentID
    var id: String

    /// 원문(검색 기준 1)
    var raw: String

    /// 표시 이름(검색 기준 2)
    var displayName: String

    /// 연결된 컨셉 ID (예: "concept_streetwear")
    var conceptId: String
}
