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
    @Published private(set) var latestSeasonImportJob: SeasonImportJob?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var importJobErrorMessage: String?

    private var loadedBrandID: BrandID?
    private var isRequesting: Bool = false

    /// 최초 진입 시 중복 로드 방지
    func loadContentsIfNeeded(
        brandID: BrandID,
        seasonRepository: any SeasonRepositoryProtocol,
        seasonImportJobRepository: any SeasonImportJobRepositoryProtocol
    ) async {
        if loadedBrandID == brandID, !seasons.isEmpty { return }
        await fetchAll(
            brandID: brandID,
            seasonRepository: seasonRepository,
            seasonImportJobRepository: seasonImportJobRepository,
            force: false
        )
    }

    /// 시즌 추가 후(시트 닫힘 등) 강제 새로고침
    func refreshContents(
        brandID: BrandID,
        seasonRepository: any SeasonRepositoryProtocol,
        seasonImportJobRepository: any SeasonImportJobRepositoryProtocol
    ) async {
        await fetchAll(
            brandID: brandID,
            seasonRepository: seasonRepository,
            seasonImportJobRepository: seasonImportJobRepository,
            force: true
        )
    }

    private func fetchAll(
        brandID: BrandID,
        seasonRepository: any SeasonRepositoryProtocol,
        seasonImportJobRepository: any SeasonImportJobRepositoryProtocol,
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
        importJobErrorMessage = nil
        defer { isLoading = false }

        do {
            let fetched = try await seasonRepository.fetchAllSeasons(brandID: brandID)
            seasons = fetched.sorted(by: Season.defaultSort)
        } catch {
            seasons = []
            errorMessage = "시즌을 불러오지 못했습니다."
        }

        do {
            let jobs = try await seasonImportJobRepository.fetchLatestJobs(
                brandID: brandID,
                limit: 10
            )
            latestSeasonImportJob = jobs.first
        } catch {
            latestSeasonImportJob = nil
            importJobErrorMessage = "시즌 import 요청 상태를 불러오지 못했습니다."
        }
    }
}
