//
//  SeasonCandidateDiscoveryResult.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

struct SeasonCandidateDiscoveryResult: Equatable {
    let brandID: BrandID
    let sourceURL: String
    let candidateCount: Int
}
