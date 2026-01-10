//
//  TagConceptRepositoryProtocol.swift
//  OutPick
//
//  Created by 김가윤 on 1/10/26.
//

import Foundation

protocol TagConceptRepositoryProtocol {
    func fetchConcept(conceptID: String) async throws -> TagConcept

    /// whereIn 10개 제한 대응 포함
    func fetchConcepts(conceptIDs: [String]) async throws -> [TagConcept]
}
