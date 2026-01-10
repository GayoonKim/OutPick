//
//  TagConcept.swift
//  OutPick
//
//  Created by 김가윤 on 1/10/26.
//

import Foundation

/// 시즌 무드(의미/개념) 단위: /tagConcepts/{conceptId}
/// 예: concept_athleisure, concept_streetwear 등
struct TagConcept: Equatable, Codable, Identifiable {
    /// Firestore DocumentID (예: "concept_athleisure")
    var id: String

    /// 사용자에게 보여줄 이름 (예: "애슬레저")
    var displayName: String
}
