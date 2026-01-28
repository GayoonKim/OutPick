//
//  BrandDetailViewModel.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import Foundation

@MainActor
final class BrandDetailViewModel: ObservableObject {
    @Published private(set) var seasons: [Season] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    private var loadedBrandID: BrandID?
    private var isRequesting: Bool = false

    /// 최초 진입 시 중복 로드 방지
    func loadSeasonsIfNeeded(
        brandID: BrandID,
        seasonRepository: any SeasonRepositoryProtocol
    ) async {
        if loadedBrandID == brandID, !seasons.isEmpty { return }
        await fetchAll(brandID: brandID, seasonRepository: seasonRepository, force: false)
    }

    /// 시즌 추가 후(시트 닫힘 등) 강제 새로고침
    func refreshSeasons(
        brandID: BrandID,
        seasonRepository: any SeasonRepositoryProtocol
    ) async {
        await fetchAll(brandID: brandID, seasonRepository: seasonRepository, force: true)
    }

    private func fetchAll(
        brandID: BrandID,
        seasonRepository: any SeasonRepositoryProtocol,
        force: Bool
    ) async {
        if isRequesting { return }
        isRequesting = true
        defer { isRequesting = false }

        if !force, loadedBrandID == brandID, !seasons.isEmpty {
            return
        }

        loadedBrandID = brandID
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetched = try await seasonRepository.fetchAllSeasons(brandID: brandID)
            seasons = fetched.sorted(by: Season.defaultSort)
        } catch {
            seasons = []
            errorMessage = "시즌을 불러오지 못했습니다."
        }
    }
}
