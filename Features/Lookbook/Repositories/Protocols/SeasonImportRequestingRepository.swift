//
//  SeasonImportRequestingRepository.swift
//  OutPick
//
//  Created by Codex on 4/23/26.
//

import Foundation

/// 시즌 URL 기반 import 요청을 서버에 위임하는 저장소 추상화입니다.
/// - Note: 실제 수집 워커와 분리해, 앱은 "요청 생성" 책임만 갖도록 유지합니다.
protocol SeasonImportRequestingRepository {
    func requestSeasonImport(
        brandID: BrandID,
        seasonURL: String
    ) async throws -> SeasonImportRequestReceipt
}
